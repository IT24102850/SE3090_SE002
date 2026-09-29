using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.Authorization;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using System.Security.Claims;

namespace SmeBackend.Tests;

public class InventoryControllerTests
{
    [Fact]
    public async Task GetCategories_WhenLegacyTenantHasNoCatalog_SeedsBusinessCategories()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Tenants.Add(new Tenant { Id = tenantId, Name = "Clinic", BusinessType = "clinic" });
        await db.SaveChangesAsync();
        db.InventoryCategories.RemoveRange(db.InventoryCategories);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.GetCategories(CancellationToken.None);

        var categories = Assert.IsType<OkObjectResult>(result.Result).Value
            as IReadOnlyList<InventoryCategoryOptionResponse>;
        Assert.NotNull(categories);
        Assert.Contains(categories, category => category.Name == "Medical Supplies");
        Assert.Contains(categories, category => category.Name == "Pharmaceuticals");
        Assert.Equal(4, categories.Count);
    }

    [Fact]
    public async Task CreateInventory_WhenCategoryNameIsProvidedWithoutId_CreatesAndAssignsCategory()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Tenants.Add(new Tenant { Id = tenantId, Name = "Clinic", BusinessType = "clinic" });
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.CreateInventory(
            new CreateInventoryRequest(
                "Portable ECG",
                "ECG-001",
                null,
                null,
                null,
                null,
                Category: "Diagnostic Equipment"),
            CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(result.Result).Value
            as InventoryItemResponse;
        Assert.NotNull(created);
        Assert.Equal("Diagnostic Equipment", created.Category);
        Assert.NotNull(created.CategoryId);
        Assert.Contains(db.InventoryCategories, category =>
            category.Id == created.CategoryId && category.Name == "Diagnostic Equipment");
    }

    [Fact]
    public async Task UpdateInventoryItem_WhenCategoryNameIsProvidedWithoutId_AssignsCategory()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            Name = "Portable ECG",
            Sku = "ECG-002",
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.UpdateInventoryItem(
            item.Id,
            new UpdateInventoryRequest(
                item.Name,
                item.Sku,
                null,
                null,
                null,
                null,
                Category: "Diagnostic Equipment"),
            CancellationToken.None);

        var updated = Assert.IsType<OkObjectResult>(result.Result).Value
            as InventoryItemResponse;
        Assert.NotNull(updated);
        Assert.Equal("Diagnostic Equipment", updated.Category);
        Assert.NotNull(updated.CategoryId);
    }

    [Fact]
    public async Task GetInventory_WhenTenantIdMissing_ReturnsUnauthorized()
    {
        var db = CreateDbContext();
        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(
            db,
            authorizationService.Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity())
                }
            }
        };

        var result = await controller.GetInventory(null, false, null, 1, 20);

        Assert.IsType<UnauthorizedResult>(result.Result);
    }

    [Fact]
    public async Task AdjustInventoryItem_WhenStockIsAvailable_UpdatesQuantityAndPersistsMovement()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = "Coffee Beans",
            Sku = "SKU-001",
            BranchId = branchId,
            Quantity = 20m,
            ReorderLevel = 25m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(
            db,
            authorizationService.Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var result = await controller.AdjustInventoryItem(item.Id, new AdjustInventoryRequest(-5m, "REF-001", "Cycle count"), CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<InventoryItemResponse>(okResult.Value);

        Assert.Equal(15m, response.Quantity);
        Assert.Equal(15m, db.InventoryItems.Single(x => x.Id == item.Id).Quantity);
        Assert.Contains(db.StockMovements, x => x.InventoryItemId == item.Id && x.Reference == "REF-001" && x.Quantity == -5m);
    }

    [Fact]
    public async Task AdjustInventoryItem_WhenAdjustmentWouldGoNegative_ReturnsConflict()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = "Tea",
            Sku = "SKU-002",
            BranchId = branchId,
            Quantity = 5m,
            ReorderLevel = 10m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(
            db,
            authorizationService.Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var result = await controller.AdjustInventoryItem(item.Id, new AdjustInventoryRequest(-10m, "REF-002", "Shrinkage"), CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
    }

    [Fact]
    public async Task RecordPhysicalCount_WhenStockChangedSinceCount_ReturnsConflictWithoutAdjusting()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var countedAt = DateTime.UtcNow.AddMinutes(-10);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Coffee Beans",
            Sku = "SKU-COUNT-STALE",
            Quantity = 10m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        db.StockMovements.Add(new StockMovement
        {
            TenantId = tenantId,
            BranchId = branchId,
            InventoryItemId = item.Id,
            MovementType = "PurchaseReceived",
            Quantity = 1m,
            OccurredAt = DateTime.UtcNow.AddMinutes(-5),
            Reference = "RECEIVE-AFTER-COUNT",
        });
        db.StockMovements.Add(new StockMovement
        {
            TenantId = tenantId,
            BranchId = branchId,
            InventoryItemId = item.Id,
            MovementType = "Issue",
            Quantity = -1m,
            OccurredAt = DateTime.UtcNow.AddMinutes(-4),
            Reference = "ISSUE-AFTER-COUNT",
        });
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, userId: Guid.NewGuid())
                }
            }
        };

        var result = await controller.RecordPhysicalCount(
            item.Id,
            new RecordPhysicalCountRequest(
                8m, 10m, countedAt, "MOBILE-AUDIT-COUNT-1", "LostOrMissing"),
            CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.NotNull(conflict.Value);
        Assert.Equal(10m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Equal(2, await db.StockMovements.CountAsync());
    }

    [Fact]
    public async Task RecordPhysicalCount_WhenSnapshotIsCurrent_RecordsExactVarianceAndIsIdempotent()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Coffee Beans",
            Sku = "SKU-COUNT-CURRENT",
            Quantity = 10m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, userId: Guid.NewGuid())
                }
            }
        };
        var request = new RecordPhysicalCountRequest(
            9m,
            10m,
            DateTimeOffset.UtcNow.AddMinutes(-1),
            "MOBILE-AUDIT-COUNT-2",
            "CountingError");

        var firstResult = await controller.RecordPhysicalCount(
            item.Id,
            request,
            CancellationToken.None);
        var firstResponse = Assert.IsType<PhysicalStockCountResponse>(
            Assert.IsType<OkObjectResult>(firstResult.Result).Value);
        var secondResult = await controller.RecordPhysicalCount(
            item.Id,
            request,
            CancellationToken.None);

        Assert.Equal(9m, firstResponse.CountedQuantity);
        Assert.Equal("Applied", firstResponse.Status);
        Assert.IsType<OkObjectResult>(secondResult.Result);
        var movement = Assert.Single(await db.StockMovements.ToListAsync());
        Assert.Equal(-1m, movement.Quantity);
        Assert.Equal("Adjustment", movement.MovementType);
        Assert.Equal("MOBILE-AUDIT-COUNT-2", movement.Reference);
        Assert.Contains("CountingError", movement.Notes);
    }

    [Fact]
    public async Task RecordPhysicalCount_WhenVarianceHasNoReason_RejectsWithoutChangingStock()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = Guid.NewGuid(),
            Name = "Coffee Beans",
            Sku = "SKU-COUNT-NO-REASON",
            Quantity = 10m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();
        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, userId: Guid.NewGuid())
                }
            }
        };

        var result = await controller.RecordPhysicalCount(
            item.Id,
            new RecordPhysicalCountRequest(
                9m,
                10m,
                DateTimeOffset.UtcNow,
                "MOBILE-AUDIT-NO-REASON",
                null!),
            CancellationToken.None);

        var badRequest = Assert.IsType<ObjectResult>(result.Result);
        var validation = Assert.IsType<ValidationProblemDetails>(badRequest.Value);
        Assert.NotEmpty(validation.Errors);
        Assert.Equal(10m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Empty(await db.PhysicalStockCounts.ToListAsync());
        Assert.Empty(await db.StockMovements.ToListAsync());
    }

    [Fact]
    public async Task ReviewPhysicalCount_WhenRejected_RecordsReviewerWithoutAdjustingStock()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var counterId = Guid.NewGuid();
        var managerId = Guid.NewGuid();
        var item = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = Guid.NewGuid(),
            Name = "Coffee Beans",
            Sku = "SKU-COUNT-REJECT",
            Quantity = 100m,
            IsActive = true,
        };
        var count = new PhysicalStockCount
        {
            TenantId = tenantId,
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            ItemName = item.Name,
            Sku = item.Sku,
            SystemQuantityAtCount = 100m,
            CountedQuantity = 89m,
            Variance = -11m,
            Reason = "LostOrMissing",
            CountedAt = DateTime.UtcNow.AddMinutes(-1),
            CountedByUserId = counterId,
            CountedBy = "Counter",
            Reference = "MOBILE-AUDIT-REJECT",
            Status = "PendingApproval",
        };
        db.InventoryItems.Add(item);
        db.PhysicalStockCounts.Add(count);
        await db.SaveChangesAsync();
        var controller = new PhysicalStockCountsController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<ICloudinaryImageService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, UserRole.Manager, managerId)
                }
            }
        };

        var result = await controller.ReviewPhysicalCount(
            count.Id,
            new ReviewPhysicalStockCountRequest("Reject", "Count was not verified."),
            CancellationToken.None);
        var response = Assert.IsType<PhysicalStockCountResponse>(
            Assert.IsType<OkObjectResult>(result.Result).Value);

        Assert.Equal("Rejected", response.Status);
        Assert.Equal("Count was not verified.", response.ReviewNotes);
        Assert.Equal(managerId, (await db.PhysicalStockCounts.SingleAsync()).ReviewedByUserId);
        var notification = Assert.Single(await db.Notifications.ToListAsync());
        Assert.Equal(counterId, notification.UserId);
        Assert.Equal("PhysicalCountRejected", notification.Type);
        Assert.Equal(100m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Empty(await db.StockMovements.ToListAsync());
    }

    [Fact]
    public async Task UploadPhoto_WhenImageServiceIsUnconfigured_ReturnsClearServiceUnavailable()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var count = new PhysicalStockCount
        {
            TenantId = tenantId,
            InventoryItemId = Guid.NewGuid(),
            BranchId = Guid.NewGuid(),
            ItemName = "Coffee Beans",
            Sku = "SKU-COUNT-PHOTO",
            SystemQuantityAtCount = 10m,
            CountedQuantity = 9m,
            Variance = -1m,
            Reason = "DamagedStock",
            CountedAt = DateTime.UtcNow,
            CountedBy = "Counter",
            Reference = "MOBILE-AUDIT-PHOTO",
            Status = "Applied",
        };
        db.PhysicalStockCounts.Add(count);
        await db.SaveChangesAsync();
        var imageService = new Mock<ICloudinaryImageService>();
        imageService
            .Setup(service => service.UploadAsync(
                It.IsAny<Stream>(),
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<CancellationToken>()))
            .ThrowsAsync(new CloudinaryNotConfiguredException());
        var controller = new PhysicalStockCountsController(
            db,
            CreateAuthorizationService().Object,
            imageService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };
        await using var stream = new MemoryStream(new byte[] { 1 });
        var file = new FormFile(stream, 0, 1, "file", "evidence.jpg")
        {
            Headers = new HeaderDictionary(),
            ContentType = "image/jpeg",
        };

        var result = await controller.UploadPhoto(
            count.Id,
            file,
            "local-count-1-0",
            CancellationToken.None);

        var unavailable = Assert.IsType<ObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status503ServiceUnavailable, unavailable.StatusCode);
        Assert.Contains("not configured", unavailable.Value!.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.Null((await db.PhysicalStockCounts.SingleAsync()).PhotoUrlsJson);
    }

    [Fact]
    public async Task UploadPhoto_WhenRetriedWithSameKey_DoesNotUploadDuplicateEvidence()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var count = new PhysicalStockCount
        {
            TenantId = tenantId,
            InventoryItemId = Guid.NewGuid(),
            BranchId = Guid.NewGuid(),
            ItemName = "Coffee Beans",
            Sku = "SKU-COUNT-PHOTO-RETRY",
            SystemQuantityAtCount = 10m,
            CountedQuantity = 9m,
            Variance = -1m,
            Reason = "DamagedStock",
            CountedAt = DateTime.UtcNow,
            CountedBy = "Counter",
            Reference = "MOBILE-AUDIT-PHOTO-RETRY",
            Status = "Applied",
        };
        db.PhysicalStockCounts.Add(count);
        await db.SaveChangesAsync();
        var imageService = new Mock<ICloudinaryImageService>();
        imageService
            .Setup(service => service.UploadAsync(
                It.IsAny<Stream>(),
                It.IsAny<string>(),
                "stock-count-evidence",
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UploadedImage(
                "https://images.example.test/evidence.jpg",
                "stock-count/evidence"));
        var controller = new PhysicalStockCountsController(
            db,
            CreateAuthorizationService().Object,
            imageService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };
        await using var stream = new MemoryStream(new byte[] { 1 });
        var file = new FormFile(stream, 0, 1, "file", "evidence.jpg")
        {
            Headers = new HeaderDictionary(),
            ContentType = "image/jpeg",
        };

        var first = await controller.UploadPhoto(
            count.Id,
            file,
            "local-count-1-0",
            CancellationToken.None);
        var retry = await controller.UploadPhoto(
            count.Id,
            file,
            "local-count-1-0",
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(first.Result);
        Assert.IsType<OkObjectResult>(retry.Result);
        imageService.Verify(service => service.UploadAsync(
            It.IsAny<Stream>(),
            It.IsAny<string>(),
            "stock-count-evidence",
            It.IsAny<CancellationToken>()), Times.Once);
        var savedCount = await db.PhysicalStockCounts.SingleAsync();
        Assert.Single(System.Text.Json.JsonSerializer.Deserialize<List<string>>(
            savedCount.PhotoUrlsJson!)!);
        Assert.Single(System.Text.Json.JsonSerializer.Deserialize<List<string>>(
            savedCount.PhotoUploadKeysJson!)!);
    }

    [Fact]
    public async Task RecordPhysicalCount_LargeVarianceRequiresIndependentApproval()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var counterId = Guid.NewGuid();
        var managerId = Guid.NewGuid();
        var item = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Coffee Beans",
            Sku = "SKU-COUNT-APPROVAL",
            Quantity = 100m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var authorization = CreateAuthorizationService();
        var counter = new InventoryController(
            db,
            authorization.Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, UserRole.Staff, counterId)
                }
            }
        };
        var request = new RecordPhysicalCountRequest(
            89m,
            100m,
            DateTimeOffset.UtcNow.AddMinutes(-1),
            "MOBILE-AUDIT-COUNT-APPROVAL",
            "LostOrMissing");

        var submitted = await counter.RecordPhysicalCount(
            item.Id,
            request,
            CancellationToken.None);
        var pending = Assert.IsType<PhysicalStockCountResponse>(
            Assert.IsType<AcceptedResult>(submitted.Result).Value);
        Assert.Equal("PendingApproval", pending.Status);
        Assert.Equal(100m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Empty(await db.StockMovements.ToListAsync());

        var sameUserApprover = new PhysicalStockCountsController(
            db,
            authorization.Object,
            Mock.Of<ICloudinaryImageService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, UserRole.Manager, counterId)
                }
            }
        };
        var selfApproval = await sameUserApprover.ReviewPhysicalCount(
            pending.Id,
            new ReviewPhysicalStockCountRequest("Approve"),
            CancellationToken.None);
        Assert.IsType<ForbidResult>(selfApproval.Result);

        var approver = new PhysicalStockCountsController(
            db,
            authorization.Object,
            Mock.Of<ICloudinaryImageService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, UserRole.Manager, managerId)
                }
            }
        };
        var approved = await approver.ReviewPhysicalCount(
            pending.Id,
            new ReviewPhysicalStockCountRequest("Approve", "Verified recount"),
            CancellationToken.None);
        var applied = Assert.IsType<PhysicalStockCountResponse>(
            Assert.IsType<OkObjectResult>(approved.Result).Value);

        Assert.Equal("Applied", applied.Status);
        Assert.Equal("Authorized user", applied.ReviewedBy);
        Assert.Equal(89m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Equal(-11m, (await db.StockMovements.SingleAsync()).Quantity);
    }

    [Fact]
    public async Task IssueInventoryItem_WhenStockIsAvailable_RecordsIssueMovement()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = "Coffee Beans",
            Sku = "SKU-ISSUE",
            BranchId = branchId,
            Quantity = 20m,
            ReorderLevel = 25m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var result = await controller.IssueInventoryItem(
            item.Id,
            new AdjustInventoryRequest(5m, "MOBILE-SCANNER", "Stock checked out"),
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<InventoryItemResponse>(okResult.Value);
        var movement = Assert.Single(db.StockMovements);

        Assert.Equal(15m, response.Quantity);
        Assert.Equal("Issue", movement.MovementType);
        Assert.Equal(-5m, movement.Quantity);
        Assert.Equal("MOBILE-SCANNER", movement.Reference);
    }

    [Fact]
    public async Task RecordInventorySale_WhenQuantityIsNotPositive_ReturnsValidationProblem()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            Name = "Tea",
            Sku = "SKU-003",
            BranchId = Guid.NewGuid(),
            Quantity = 5m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.RecordInventorySale(
            item.Id,
            new RecordInventorySaleRequest(0m),
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(db.Sales);
        Assert.Equal(5m, item.Quantity);
    }

    [Fact]
    public async Task RecordInventorySale_WhenItemHasNoBranch_ReturnsConflict()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            Name = "Tea",
            Sku = "SKU-004",
            Quantity = 5m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.RecordInventorySale(
            item.Id,
            new RecordInventorySaleRequest(2m),
            CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Empty(db.Sales);
        Assert.Equal(5m, item.Quantity);
    }

    [Fact]
    public async Task RecordInventorySale_WhenSellingPriceIsNotConfigured_ReturnsConflict()
    {
        var tenantId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            TenantId = tenantId,
            Name = "Tea",
            Sku = "SKU-005",
            BranchId = Guid.NewGuid(),
            Quantity = 5m,
            UnitCost = 80m,
            SellingPrice = null,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var controller = new InventoryController(
            db,
            CreateAuthorizationService().Object,
            Mock.Of<IInventoryAgentService>(),
            Mock.Of<IJwtService>())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.RecordInventorySale(
            item.Id,
            new RecordInventorySaleRequest(2m),
            CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Empty(db.Sales);
        Assert.Equal(5m, item.Quantity);
    }

    private static Mock<IAuthorizationService> CreateAuthorizationService()
    {
        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService
            .Setup(x => x.AuthorizeAsync(It.IsAny<ClaimsPrincipal>(), It.IsAny<object>(), It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        return authorizationService;
    }

    private static ClaimsPrincipal CreateUser(
        Guid tenantId,
        UserRole role = UserRole.Admin,
        Guid? userId = null)
    {
        var claims = new List<Claim>
        {
            new(InventoryAccessHandler.TenantIdClaimType, tenantId.ToString()),
            new(ClaimTypes.Role, role.ToString()),
        };
        if (userId.HasValue)
            claims.Add(new Claim(ClaimTypes.NameIdentifier, userId.Value.ToString()));
        var identity = new ClaimsIdentity(claims, "TestAuth");

        return new ClaimsPrincipal(identity);
    }

    private static AppDbContext CreateDbContext(ITenantContext? tenantContext = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new AppDbContext(options, tenantContext ?? new TenantContext());
    }
}

public class InventoryAnalyticsTests
{
    [Fact]
    public void Predict_WhenUsageHistoryExists_ReturnsAverageAndSafetyStock()
    {
        var result = InventoryDemandPrediction.Predict(new[] { 12m, 18m, 30m }, forecastDays: 7, leadTimeDays: 7, safetyStockDays: 7);

        Assert.Equal(20m, result.AverageDailyDemand);
        Assert.Equal(140m, result.PredictedTotalDemand);
        Assert.Equal(140m, result.SafetyStock);
        Assert.InRange(result.Confidence, 0.55m, 0.99m);
    }

    [Fact]
    public void Calculate_WhenCurrentStockIsLow_UsesReorderFloorAndOrderMultiple()
    {
        var result = InventoryStockAdjustment.Calculate(
            currentStock: 18m,
            reorderLevel: 25m,
            predictedDemand: 98m,
            leadTimeDays: 7,
            safetyStockDays: 7,
            unitCost: 2.45m,
            orderMultiple: 10,
            budgetLimit: 1000m);

        Assert.Equal(180m, result.RecommendedQuantity);
        Assert.Equal("high", result.Priority);
        Assert.Equal(441m, result.TotalCost);
    }
}

public class PurchaseOrdersControllerTests
{
    [Fact]
    public async Task CreatePurchaseOrder_WithItems_PersistsItemsAndComputesTotals()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();
        var itemId = Guid.NewGuid();

        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.Add(new Supplier { Id = supplierId, TenantId = tenantId, Name = "Acme Supplies" });
        db.InventoryItems.Add(new InventoryItem
        {
            Id = itemId,
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Organic Coffee",
            Sku = "SKU-COF-01",
            Quantity = 10,
            SupplierId = supplierId,
            UnitCost = 1500m,
            IsActive = true,
        });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var request = new CreatePurchaseOrderRequest(
            branchId,
            supplierId,
            "PO-TEST-001",
            "Draft",
            new List<PurchaseOrderItemRequest>
            {
                new(itemId, null, 10m, 1500m),
                new(null, "Paper cups (x100)", 5m, 800m),
            });

        var actionResult = await controller.CreatePurchaseOrder(request, CancellationToken.None);
        var createdResult = Assert.IsType<CreatedAtActionResult>(actionResult.Result);
        var response = Assert.IsType<PurchaseOrderResponse>(createdResult.Value);

        Assert.Equal("PO-TEST-001", response.Number);
        Assert.Equal(2, response.LineItems);
        Assert.Equal(19000m, response.TotalAmount);
        Assert.NotNull(response.Items);
        Assert.Equal(2, response.Items!.Count);
        var coffeeItem = response.Items.Single(i => i.InventoryItemId == itemId);
        Assert.Equal("Organic Coffee", coffeeItem.ItemName);
        Assert.Equal(10m, coffeeItem.Quantity);
        Assert.Equal(1500m, coffeeItem.UnitPrice);
        Assert.Equal(15000m, coffeeItem.LineTotal);

        var customItem = response.Items.Single(i => i.InventoryItemId == null);
        Assert.Equal("Paper cups (x100)", customItem.Description);
        Assert.Equal(5m, customItem.Quantity);
        Assert.Equal(800m, customItem.UnitPrice);
        Assert.Equal(4000m, customItem.LineTotal);
    }

    [Theory]
    [InlineData(false, 1400.0)]
    [InlineData(true, 1500.0)]
    public async Task CreatePurchaseOrder_RejectsCatalogPriceOrSupplierMismatch(
        bool useDifferentSupplier,
        double requestedUnitPrice)
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();
        var otherSupplierId = Guid.NewGuid();
        var itemId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.AddRange(
            new Supplier { Id = supplierId, TenantId = tenantId, Name = "Catalog Supplier" },
            new Supplier { Id = otherSupplierId, TenantId = tenantId, Name = "Different Supplier" });
        db.InventoryItems.Add(new InventoryItem
        {
            Id = itemId,
            TenantId = tenantId,
            BranchId = branchId,
            SupplierId = supplierId,
            Name = "Organic Coffee",
            Sku = "SKU-COF-02",
            Quantity = 10,
            UnitCost = 1500m,
            IsActive = true,
        });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());
        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.CreatePurchaseOrder(
            new CreatePurchaseOrderRequest(
                branchId,
                useDifferentSupplier ? otherSupplierId : supplierId,
                "PO-CATALOG-VALIDATION",
                "Draft",
                [new PurchaseOrderItemRequest(itemId, null, 1m, (decimal)requestedUnitPrice)]),
            CancellationToken.None);

        Assert.IsType<ObjectResult>(result.Result);
        Assert.Empty(await db.PurchaseOrders.ToListAsync());
    }

    [Fact]
    public async Task CreatePurchaseOrder_WithNegativeQuantity_ReturnsValidationProblem()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();

        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.Add(new Supplier { Id = supplierId, TenantId = tenantId, Name = "Acme Supplies" });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var request = new CreatePurchaseOrderRequest(
            branchId,
            supplierId,
            "PO-TEST-002",
            "Draft",
            new List<PurchaseOrderItemRequest>
            {
                new(null, "Test item", -5m, 100m),
            });

        var actionResult = await controller.CreatePurchaseOrder(request, CancellationToken.None);
        Assert.IsType<ObjectResult>(actionResult.Result);
    }

    [Fact]
    public async Task CreatePurchaseOrder_CannotStartAlreadyPlaced()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.Add(new Supplier { Id = supplierId, TenantId = tenantId, Name = "Acme Supplies" });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());
        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = CreateUser(tenantId) }
            }
        };

        var result = await controller.CreatePurchaseOrder(
            new CreatePurchaseOrderRequest(branchId, supplierId, "PO-BYPASS", "Placed"),
            CancellationToken.None);

        Assert.IsType<ObjectResult>(result.Result);
        Assert.Empty(await db.PurchaseOrders.ToListAsync());
    }

    [Fact]
    public async Task UpdatePurchaseOrderStatus_WebTokenCanApproveInReviewOrder()
    {
        var tenantId = Guid.NewGuid();
        var (db, controller) = await CreateControllerWithOrder(tenantId, "InReview");
        await using var disposeDb = db;

        var result = await controller.UpdatePurchaseOrderStatus(
            Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            new UpdatePurchaseOrderStatusRequest("Placed"),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal("Placed", (await db.PurchaseOrders.SingleAsync()).Status);
    }

    [Fact]
    public async Task UpdatePurchaseOrderStatus_MobileTokenCanApproveInReviewOrder()
    {
        var tenantId = Guid.NewGuid();
        var (db, controller) = await CreateControllerWithOrder(tenantId, "InReview", mobileClient: true);
        await using var disposeDb = db;

        var result = await controller.UpdatePurchaseOrderStatus(
            Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            new UpdatePurchaseOrderStatusRequest("Placed"),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal("Placed", (await db.PurchaseOrders.SingleAsync()).Status);
    }

    [Fact]
    public async Task UpdatePurchaseOrderStatus_MobileTokenCannotSkipReview()
    {
        var tenantId = Guid.NewGuid();
        var (db, controller) = await CreateControllerWithOrder(tenantId, "Draft", mobileClient: true);
        await using var disposeDb = db;

        var result = await controller.UpdatePurchaseOrderStatus(
            Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            new UpdatePurchaseOrderStatusRequest("Placed"),
            CancellationToken.None);

        Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal("Draft", (await db.PurchaseOrders.SingleAsync()).Status);
    }

    [Fact]
    public async Task UpdatePurchaseOrderStatus_ApprovalIsNotBoundToRequestOrigin()
    {
        var tenantId = Guid.NewGuid();
        var (db, controller) = await CreateControllerWithOrder(
            tenantId,
            "InReview",
            mobileClient: true,
            browserOrigin: true);
        await using var disposeDb = db;

        var result = await controller.UpdatePurchaseOrderStatus(
            Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            new UpdatePurchaseOrderStatusRequest("Placed"),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal("Placed", (await db.PurchaseOrders.SingleAsync()).Status);
    }

    [Fact]
    public async Task ReceivePurchaseOrder_OnlyAddsAcceptedUnitsAndRecordsShortageAndDamage()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var itemId = Guid.NewGuid();
        var poItemId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        await using var db = CreateDbContext(tenantContext);
        var order = new PurchaseOrder
        {
            TenantId = tenantId,
            BranchId = branchId,
            SupplierId = Guid.NewGuid(),
            Number = "PO-RECEIVE-001",
            Status = "InTransit",
        };
        var inventoryItem = new InventoryItem
        {
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Coke",
            Sku = "COKE-001",
            Quantity = 10m,
            UnitCost = 5m,
            IsActive = true,
        };
        var orderItem = new PurchaseOrderItem
        {
            Id = poItemId,
            TenantId = tenantId,
            PurchaseOrderId = order.Id,
            Description = "Coke",
            Quantity = 10m,
            UnitPrice = 6m,
        };
        inventoryItem.Id = itemId;
        db.PurchaseOrders.Add(order);
        db.PurchaseOrderItems.Add(orderItem);
        db.InventoryItems.Add(inventoryItem);
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());
        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId, mobileClient: false, role: UserRole.Staff, fullName: "Receiving Staff")
                }
            }
        };

        var firstResult = await controller.ReceivePurchaseOrder(
            order.Id,
            new ReceivePurchaseOrderRequest(
            [
                new ReceivePurchaseOrderItemRequest(poItemId, 1m, 1m, false, "One bottle damaged", itemId)
            ]),
            CancellationToken.None);

        var firstResponse = Assert.IsType<PurchaseOrderResponse>(
            Assert.IsType<OkObjectResult>(firstResult.Result).Value);
        Assert.Equal("PartiallyReceived", firstResponse.Status);
        Assert.Equal(2m, (await db.PurchaseOrderReceipts.SingleAsync()).Items.Single().DeliveredQuantity);
        Assert.Equal(1m, firstResponse.Items!.Single().ReceivedQuantity);
        Assert.Equal(1m, firstResponse.Items!.Single().DamagedQuantity);
        Assert.Equal(11m, inventoryItem.Quantity);
        var acceptedMovement = await db.StockMovements.SingleAsync();
        Assert.Equal(1m, acceptedMovement.Quantity);
        Assert.Equal("Receiving Staff", acceptedMovement.PerformedBy);
        Assert.Contains("Damaged: 1", acceptedMovement.Notes);

        var secondResult = await controller.ReceivePurchaseOrder(
            order.Id,
            new ReceivePurchaseOrderRequest(
            [
                new ReceivePurchaseOrderItemRequest(poItemId, 1m, 0m, true, "Supplier confirmed one unit short")
            ]),
            CancellationToken.None);

        var secondResponse = Assert.IsType<PurchaseOrderResponse>(
            Assert.IsType<OkObjectResult>(secondResult.Result).Value);
        Assert.Equal("Received", secondResponse.Status);
        Assert.Equal(2m, secondResponse.Items!.Single().ReceivedQuantity);
        Assert.Equal(1m, secondResponse.Items!.Single().DamagedQuantity);
        Assert.Equal(7m, secondResponse.Items!.Single().ShortageQuantity);
        Assert.Equal(12m, inventoryItem.Quantity);
        Assert.Equal(2, secondResponse.Receipts!.Count);
        Assert.Equal(2m, (await db.StockMovements.SumAsync(movement => movement.Quantity)));
    }

    [Fact]
    public async Task UpdatePurchaseOrderStatus_CannotReceiveWithoutItemizedReceipt()
    {
        var tenantId = Guid.NewGuid();
        var (db, controller) = await CreateControllerWithOrder(tenantId, "InTransit");
        await using var disposeDb = db;

        var result = await controller.UpdatePurchaseOrderStatus(
            Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            new UpdatePurchaseOrderStatusRequest("Received"),
            CancellationToken.None);

        Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal("InTransit", (await db.PurchaseOrders.SingleAsync()).Status);
        Assert.Empty(db.StockMovements);
    }

    private static async Task<(AppDbContext Db, PurchaseOrdersController Controller)> CreateControllerWithOrder(
        Guid tenantId,
        string status,
        bool mobileClient = false,
        bool browserOrigin = false)
    {
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        var db = CreateDbContext(tenantContext);
        db.PurchaseOrders.Add(new PurchaseOrder
        {
            Id = Guid.Parse("9f95fa89-1018-49de-a82e-3442303956a1"),
            TenantId = tenantId,
            BranchId = Guid.NewGuid(),
            SupplierId = Guid.NewGuid(),
            Number = "PO-TEST-APPROVAL",
            Status = status,
        });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());
        var httpContext = new DefaultHttpContext { User = CreateUser(tenantId, mobileClient) };
        if (browserOrigin)
            httpContext.Request.Headers["Origin"] = "https://web.example.test";
        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
        return (db, controller);
    }

    private static ClaimsPrincipal CreateUser(
        Guid tenantId,
        bool mobileClient = false,
        UserRole role = UserRole.Admin,
        string? fullName = null)
    {
        var claims = new List<Claim>
        {
            new Claim(InventoryAccessHandler.TenantIdClaimType, tenantId.ToString()),
            new Claim(ClaimTypes.Role, role.ToString()),
        };
        if (fullName is not null)
            claims.Add(new Claim("fullName", fullName));
        if (mobileClient)
            claims.Add(new Claim(InventoryAccessHandler.ClientPlatformClaimType, "mobile"));
        return new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"));
    }

    private static AppDbContext CreateDbContext(ITenantContext? tenantContext = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new AppDbContext(options, tenantContext ?? new TenantContext());
    }
}
