using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Authorization;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize(Roles = "Admin")]
[Route("api/users")]
public sealed class UsersController(AppDbContext db, IEntitlementService entitlements) : ControllerBase
{
    [HttpGet("branches")]
    public async Task<ActionResult<IReadOnlyList<BranchResponse>>> GetBranches(CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var branches = await db.Branches.IgnoreQueryFilters().AsNoTracking()
            .Where(branch => branch.TenantId == tenantId && branch.IsActive)
            .OrderBy(branch => branch.Name)
            .Select(branch => new BranchResponse(branch.Id, branch.Name))
            .ToListAsync(cancellationToken);
        return Ok(branches);
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<UserResponse>>> GetUsers(CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var users = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(user => user.TenantId == tenantId && user.Tenant.IsActive && user.IsApproved)
            .OrderBy(user => user.FullName)
            .Select(user => new UserResponse(user.Id, user.FullName, user.Email, user.Phone, user.Role.ToString(), user.BranchId, user.IsApproved))
            .ToListAsync(cancellationToken);
        return Ok(users);
    }

    [HttpGet("pending")]
    public async Task<ActionResult<IReadOnlyList<UserResponse>>> GetPendingUsers(CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var users = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(user => user.TenantId == tenantId && !user.IsApproved && user.Tenant.IsActive)
            .OrderBy(user => user.CreatedAt)
            .Select(user => new UserResponse(user.Id, user.FullName, user.Email, user.Phone, user.Role.ToString(), user.BranchId, user.IsApproved))
            .ToListAsync(cancellationToken);
        return Ok(users);
    }

    [HttpPost]
    public async Task<ActionResult<UserResponse>> CreateUser(CreateUserRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var email = request.Email.Trim().ToLowerInvariant();
        if (!Enum.TryParse<UserRole>(request.Role, true, out var role) || !IsTenantRole(role) ||
            string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(email) ||
            string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
        {
            return BadRequest(new { message = "Provide a name, Admin, Manager, or Staff role, email, and password of at least 8 characters." });
        }
        if (await db.Users.IgnoreQueryFilters().AnyAsync(user => user.Email == email, cancellationToken))
        {
            return Conflict(new { message = "An account with this email already exists." });
        }

        if (request.BranchId.HasValue && !await db.Branches.IgnoreQueryFilters().AnyAsync(branch => branch.TenantId == tenantId && branch.Id == request.BranchId.Value && branch.IsActive, cancellationToken))
        {
            return BadRequest(new { message = "The selected branch does not belong to your tenant." });
        }

        // Seats are a plan limit. Customers are not seats - they are the
        // tenant's own clientele, and charging a business per customer would
        // punish exactly the growth we are selling.
        var seatsUsed = await db.Users.IgnoreQueryFilters()
            .CountAsync(u => u.TenantId == tenantId && u.Role != UserRole.Customer && u.IsActive, cancellationToken);
        if (await entitlements.CheckCapAsync(tenantId, EntitlementService.CapStaffSeats, seatsUsed, cancellationToken) is { } paywall)
            return PlanGate.PaymentRequired(paywall);

        var user = new User
        {
            TenantId = tenantId,
            FullName = request.FullName.Trim(),
            Email = email,
            Phone = request.Phone?.Trim() ?? string.Empty,
            Role = role,
            BranchId = request.BranchId,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            IsApproved = true,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync(cancellationToken);
        entitlements.Invalidate(tenantId);
        return CreatedAtAction(nameof(GetUsers), new { }, new UserResponse(user.Id, user.FullName, user.Email, user.Phone, user.Role.ToString(), user.BranchId, user.IsApproved));
    }

    [HttpPut("{id:guid}/approve")]
    public async Task<ActionResult<UserResponse>> ApproveUser(Guid id, ApproveUserRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        if (!Enum.TryParse<UserRole>(request.Role, true, out var role) || !IsTenantRole(role))
            return BadRequest(new { message = "Role must be Admin, Manager, or Staff." });
        var user = await db.Users.IgnoreQueryFilters().SingleOrDefaultAsync(candidate =>
            candidate.Id == id && candidate.TenantId == tenantId && !candidate.IsApproved && candidate.Tenant.IsActive, cancellationToken);
        if (user is null) return NotFound(new { message = "Pending signup request not found." });
        if (!await db.Branches.IgnoreQueryFilters().AnyAsync(branch => branch.TenantId == tenantId && branch.Id == request.BranchId && branch.IsActive, cancellationToken))
            return BadRequest(new { message = "Select a valid branch for this user." });
        user.Role = role;
        user.BranchId = request.BranchId;
        user.IsApproved = true;
        await db.SaveChangesAsync(cancellationToken);
        return Ok(new UserResponse(user.Id, user.FullName, user.Email, user.Phone, user.Role.ToString(), user.BranchId, user.IsApproved));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<UserResponse>> UpdateUser(Guid id, UpdateUserRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var user = await db.Users.IgnoreQueryFilters().SingleOrDefaultAsync(candidate => candidate.Id == id && candidate.TenantId == tenantId && candidate.Tenant.IsActive, cancellationToken);
        if (user is null) return NotFound();
        if (!Enum.TryParse<UserRole>(request.Role, true, out var role) || !IsTenantRole(role))
        {
            return BadRequest(new { message = "Role must be Admin, Manager, or Staff." });
        }
        var currentUserId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (Guid.TryParse(currentUserId, out var currentId) && currentId == id && role != UserRole.Admin)
        {
            return BadRequest(new { message = "You cannot remove your own Admin access." });
        }
        if (user.Role == UserRole.Admin && user.IsApproved && user.IsActive && role != UserRole.Admin &&
            await CountActiveAdmins(tenantId, cancellationToken) <= 1)
        {
            return BadRequest(new { message = "Each business must have at least one active Admin." });
        }
        if (request.BranchId.HasValue && !await db.Branches.IgnoreQueryFilters().AnyAsync(branch => branch.TenantId == tenantId && branch.Id == request.BranchId.Value && branch.IsActive, cancellationToken))
        {
            return BadRequest(new { message = "The selected branch does not belong to your tenant." });
        }
        user.FullName = request.FullName.Trim();
        user.Phone = request.Phone?.Trim() ?? string.Empty;
        user.Role = role;
        user.BranchId = request.BranchId;
        if (!string.IsNullOrWhiteSpace(request.Password))
        {
            if (request.Password.Length < 8) return BadRequest(new { message = "Password must contain at least 8 characters." });
            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);
        }
        await db.SaveChangesAsync(cancellationToken);
        return Ok(new UserResponse(user.Id, user.FullName, user.Email, user.Phone, user.Role.ToString(), user.BranchId, user.IsApproved));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteUser(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var currentUserId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (Guid.TryParse(currentUserId, out var currentId) && currentId == id)
            return BadRequest(new { message = "You cannot delete your own account." });
        var user = await db.Users.IgnoreQueryFilters().SingleOrDefaultAsync(candidate =>
            candidate.Id == id && candidate.TenantId == tenantId && candidate.Tenant.IsActive, cancellationToken);
        if (user is null) return NotFound();
        if (user.Role == UserRole.Admin && user.IsApproved && user.IsActive &&
            await CountActiveAdmins(tenantId, cancellationToken) <= 1)
        {
            return BadRequest(new { message = "Each business must have at least one active Admin." });
        }
        db.Users.Remove(user);
        await db.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    private Task<int> CountActiveAdmins(Guid tenantId, CancellationToken cancellationToken) =>
        db.Users.IgnoreQueryFilters().CountAsync(user =>
            user.TenantId == tenantId && user.Role == UserRole.Admin && user.IsApproved && user.IsActive,
            cancellationToken);

    private static bool IsTenantRole(UserRole role) =>
        role is UserRole.Admin or UserRole.Manager or UserRole.Staff;

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);
}

public sealed record UserResponse(Guid Id, string FullName, string Email, string Phone, string Role, Guid? BranchId, bool IsApproved);
public sealed record BranchResponse(Guid Id, string Name);
public sealed record CreateUserRequest(string FullName, string Email, string Password, string Role, Guid? BranchId, string? Phone = null);
public sealed record UpdateUserRequest(string FullName, string Role, Guid? BranchId, string? Password, string? Phone = null);
public sealed record ApproveUserRequest(string Role, Guid BranchId);
