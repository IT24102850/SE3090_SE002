using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Npgsql;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.Billing;
using SmeBackend.Shared;
using Testcontainers.PostgreSql;

namespace SmeBackend.Tests.Billing;

/// Real-PostgreSQL tests (spec 3.9: transaction integrity, constraint
/// enforcement, migration tests), plus a pass through every billing query
/// so a LINQ expression Npgsql cannot translate fails here rather than in
/// production.
///
/// Database: SME_TEST_POSTGRES (a server connection string; each test gets
/// its own throwaway database) or, failing that, a Testcontainers Postgres.
/// With neither available the tests return early, like the existing
/// DatabaseIntegrationTests.
public class BillingDatabaseIntegrationTests
{
    private sealed class TestDatabase : IAsyncDisposable
    {
        private readonly PostgreSqlContainer? _container;
        private readonly string? _serverConnection;
        private readonly string? _databaseName;
        public string ConnectionString { get; }

        private TestDatabase(string connectionString, PostgreSqlContainer? container, string? serverConnection, string? databaseName)
        {
            ConnectionString = connectionString;
            _container = container;
            _serverConnection = serverConnection;
            _databaseName = databaseName;
        }

        public static async Task<TestDatabase?> CreateAsync()
        {
            var server = Environment.GetEnvironmentVariable("SME_TEST_POSTGRES");
            if (!string.IsNullOrWhiteSpace(server))
            {
                var name = "billing_it_" + Guid.NewGuid().ToString("N")[..12];
                await using (var conn = new NpgsqlConnection(server))
                {
                    await conn.OpenAsync();
                    await using var cmd = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", conn);
                    await cmd.ExecuteNonQueryAsync();
                }
                var builder = new NpgsqlConnectionStringBuilder(server) { Database = name };
                return new TestDatabase(builder.ConnectionString, null, server, name);
            }

            try
            {
                var container = new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();
                await container.StartAsync();
                return new TestDatabase(container.GetConnectionString(), container, null, null);
            }
            catch
            {
                return null;
            }
        }

        public AppDbContext NewContext(Guid? tenantId = null)
        {
            var tenant = new TenantContext();
            if (tenantId.HasValue) tenant.SetTenantId(tenantId.Value);
            return new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(ConnectionString).Options, tenant);
        }

        public async ValueTask DisposeAsync()
        {
            if (_container is not null) await _container.DisposeAsync();
            if (_serverConnection is not null && _databaseName is not null)
            {
                NpgsqlConnection.ClearAllPools();
                await using var conn = new NpgsqlConnection(_serverConnection);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{_databaseName}\" WITH (FORCE)", conn);
                await cmd.ExecuteNonQueryAsync();
            }
        }
    }

    private static async Task<(Guid TenantId, User Staff, User Customer)> SeedAsync(AppDbContext db)
    {
        var tenant = new Tenant { Name = "Harbour Bistro", BusinessType = "Restaurant", IsActive = true };
        db.Tenants.Add(tenant);
        var staff = new User { TenantId = tenant.Id, Email = "till@bistro.lk", FullName = "Till", Role = UserRole.Staff, PasswordHash = "x" };
        var customer = new User { TenantId = tenant.Id, Email = "guest@example.com", FullName = "Guest", Role = UserRole.Customer, PasswordHash = "x" };
        db.Users.AddRange(staff, customer);
        await db.SaveChangesAsync();
        return (tenant.Id, staff, customer);
    }

    [Fact]
    public async Task Migrations_CreateEveryBillingTable()
    {
        await using var database = await TestDatabase.CreateAsync();
        if (database is null) return;

        await using var db = database.NewContext();
        await db.Database.MigrateAsync();

        await using var conn = new NpgsqlConnection(database.ConnectionString);
        await conn.OpenAsync();
        var tables = new HashSet<string>();
        await using (var cmd = new NpgsqlCommand("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'", conn))
        await using (var reader = await cmd.ExecuteReaderAsync())
            while (await reader.ReadAsync()) tables.Add(reader.GetString(0));

        foreach (var table in new[] { "invoices", "invoice_items", "payments", "insurance_claims", "dynamic_forms", "form_submissions",
                     "commission_rules", "payment_gateways", "invoice_templates", "Subscriptions", "agent_workflows" })
        {
            Assert.Contains(table, tables);
        }

        // payments.Status backfills existing rows as Succeeded.
        await using var def = new NpgsqlCommand(
            "SELECT column_default FROM information_schema.columns WHERE table_name = 'payments' AND column_name = 'Status'", conn);
        Assert.Contains("Succeeded", (string)(await def.ExecuteScalarAsync())!);
    }

    [Fact]
    public async Task InvoiceNumbers_AreUniquePerTenant_ButMayRepeatAcrossTenants()
    {
        await using var database = await TestDatabase.CreateAsync();
        if (database is null) return;

        await using var db = database.NewContext();
        await db.Database.MigrateAsync();
        var (tenantA, _, customerA) = await SeedAsync(db);
        var (tenantB, _, customerB) = await SeedAsync(db);

        Invoice Make(Guid tenant, Guid customer) => new()
        {
            TenantId = tenant, CustomerId = customer, InvoiceNumber = "INV-0001", TotalAmount = 10, FinalAmount = 10,
            Status = "Issued", DueDate = DateTime.UtcNow, Currency = "LKR",
        };

        db.Invoices.Add(Make(tenantA, customerA.Id));
        db.Invoices.Add(Make(tenantB, customerB.Id));
        await db.SaveChangesAsync();

        db.Invoices.Add(Make(tenantA, customerA.Id));
        var ex = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        Assert.Contains("23505", (ex.InnerException as PostgresException)?.SqlState ?? "");
    }

    [Fact]
    public async Task DeletingAnInvoice_CascadesItems_AndKeepsPaymentsForTheLedger()
    {
        await using var database = await TestDatabase.CreateAsync();
        if (database is null) return;

        await using var db = database.NewContext();
        await db.Database.MigrateAsync();
        var (tenantId, _, customer) = await SeedAsync(db);

        var invoice = new Invoice
        {
            TenantId = tenantId, CustomerId = customer.Id, InvoiceNumber = "INV-DEL", TotalAmount = 50, FinalAmount = 50,
            Status = "Issued", DueDate = DateTime.UtcNow, Currency = "LKR",
            Items = { new InvoiceItem { Description = "Soup", Quantity = 2, UnitPrice = 25, Amount = 50 } },
        };
        db.Invoices.Add(invoice);
        db.Payments.Add(new Payment { InvoiceId = invoice.Id, Amount = 50, Method = "Cash", PaidAt = DateTime.UtcNow });
        await db.SaveChangesAsync();

        db.Invoices.Remove(invoice);
        await db.SaveChangesAsync();

        await using var fresh = database.NewContext();
        Assert.Equal(0, await fresh.InvoiceItems.CountAsync());
        var payment = await fresh.Payments.SingleAsync();
        Assert.Null(payment.InvoiceId);
        Assert.Equal("Succeeded", payment.Status);
    }

    [Fact]
    public async Task FailedTransaction_LeavesNoPartialInvoice()
    {
        await using var database = await TestDatabase.CreateAsync();
        if (database is null) return;

        await using var db = database.NewContext();
        await db.Database.MigrateAsync();
        var (tenantId, _, customer) = await SeedAsync(db);

        await using (var tx = await db.Database.BeginTransactionAsync())
        {
            db.Invoices.Add(new Invoice
            {
                TenantId = tenantId, CustomerId = customer.Id, InvoiceNumber = "INV-TX", TotalAmount = 10, FinalAmount = 10,
                Status = "Issued", DueDate = DateTime.UtcNow, Currency = "LKR",
                Items = { new InvoiceItem { Description = "Tea", Quantity = 1, UnitPrice = 10, Amount = 10 } },
            });
            await db.SaveChangesAsync();
            // Something later in the same unit of work fails...
            await tx.RollbackAsync();
        }

        await using var fresh = database.NewContext();
        Assert.Equal(0, await fresh.Invoices.CountAsync());
        Assert.Equal(0, await fresh.InvoiceItems.CountAsync());
    }

    [Fact]
    public async Task EveryBillingQuery_TranslatesAndRunsOnPostgres()
    {
        await using var database = await TestDatabase.CreateAsync();
        if (database is null) return;

        Guid tenantId;
        User staff, customer;
        await using (var setup = database.NewContext())
        {
            await setup.Database.MigrateAsync();
            (tenantId, staff, customer) = await SeedAsync(setup);
        }

        await using var db = database.NewContext(tenantId);
        var messenger = new Mock<IBillingMessenger>();
        messenger.Setup(m => m.SendEmailAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<EmailAttachment?>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MessageDeliveryResponse("Email", "x", false, true, null, null));
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Jwt:Key"] = "integration-test-key-0123456789abcdef" }).Build();
        var processors = new PaymentProcessorFactory(new IPaymentProcessor[] { new ManualPaymentProcessor() });
        var approvals = new BillingApprovalService(db);
        var billing = new BillingService(db, approvals, messenger.Object);
        var settings = new BillingSettingsService(db, new PlatformSecretProtector(config), processors);
        var reports = new BillingReportService(db);
        var agent = new BillingAgentService(db, approvals);
        var checkout = new PaymentCheckoutService(db, processors, settings, billing, NullLogger<PaymentCheckoutService>.Instance);
        var forms = new DynamicFormService(db);
        var staffActor = new BillingActor(tenantId, staff.Id, Roles.Staff);
        var customerActor = new BillingActor(tenantId, customer.Id, Roles.Customer);
        var adminActor = new BillingActor(tenantId, staff.Id, Roles.Admin);

        // Invoices, payments, split bills, checkout
        var inv = (await billing.CreateInvoiceAsync(staffActor, BillingTestFixture.InvoiceRequest(customer.Id, 4500m, discount: 3000m))).Value!;
        var overdue = (await billing.CreateInvoiceAsync(staffActor, BillingTestFixture.InvoiceRequest(customer.Id, 800m, due: DateTime.UtcNow.AddDays(-40)))).Value!;
        Assert.True((await billing.PayInvoiceAsync(staffActor, inv.Id, new PayInvoiceRequest(500m, "Cash"))).Success);
        Assert.True((await billing.SplitPayInvoiceAsync(staffActor, inv.Id, new SplitPaymentRequest(new() { new(500m, "Card"), new(200m, "Cash") }))).Success);
        var session = await checkout.StartCheckoutAsync(customerActor, overdue.Id, new CheckoutRequest(Amount: 300m));
        Assert.True((await checkout.ConfirmCheckoutAsync(customerActor, new ConfirmCheckoutRequest(session.Value!.PaymentId))).Success);

        Assert.Equal(2, (await billing.GetInvoicesAsync(customerActor, new InvoiceQuery(From: DateTime.UtcNow.AddDays(-1), To: DateTime.UtcNow))).TotalCount);
        Assert.Single((await billing.GetInvoicesAsync(staffActor, new InvoiceQuery(Status: "Overdue"))).Items);
        Assert.Single((await billing.GetInvoicesAsync(staffActor, new InvoiceQuery(Search: inv.InvoiceNumber[^6..].ToLower()))).Items);
        Assert.True((await billing.GetReceiptAsync(customerActor, inv.Id)).Success);
        Assert.True((await billing.AdjustInvoiceAsync(staffActor, overdue.Id, new AdjustInvoiceRequest(400m, null, "Goodwill"))).Success);

        // Schedules, subscriptions
        Assert.True((await billing.CreatePaymentScheduleAsync(staffActor, new CreatePaymentScheduleRequest(customer.Id, "Catering", 9000m,
            new() { new("Deposit", null, 30m, DateTime.UtcNow), new("Balance", null, 70m, DateTime.UtcNow.AddDays(20)) }))).Success);
        var sub = (await billing.CreateSubscriptionAsync(staffActor, new CreateSubscriptionRequest(customer.Id, "Lunch club", 2000m, "Monthly",
            DateTime.UtcNow.AddMonths(-1).AddDays(-1), DateTime.UtcNow.AddDays(-1), GenerateInvoice: true))).Value!;
        Assert.NotEmpty(await billing.GetPlanOptionsAsync(customerActor));
        Assert.NotEmpty(await billing.GetRenewalCalendarAsync(staffActor, DateTime.UtcNow.AddDays(-5), DateTime.UtcNow.AddDays(5)));
        Assert.True((await billing.GetSubscriptionInvoicesAsync(customerActor, sub.Id)).Success);
        Assert.Equal(202, (await billing.CancelSubscriptionAsync(customerActor, sub.Id, new CancelSubscriptionRequest("Diet", 100m))).StatusCode);

        // Claims
        var claim = (await billing.CreateInsuranceClaimAsync(customerActor, new CreateInsuranceClaimRequest(inv.Id, "AIA", "AIA-9001", 200m))).Value!;
        Assert.True((await billing.UpdateInsuranceClaimStatusAsync(staffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("UnderReview"))).Success);
        Assert.Single((await billing.GetInsuranceClaimsAsync(customerActor, 1, 20, "UnderReview")).Items);

        // Reports, agent, approvals, automation
        Assert.True((await reports.GetDashboardAsync(tenantId, DateTime.UtcNow.AddDays(-30), DateTime.UtcNow, null)).TotalInvoiced > 0);
        Assert.True((await reports.GetOutstandingPaymentsAsync(tenantId, 0, null)).Count > 0);
        Assert.True((await reports.GetDailyRevenueAsync(tenantId, DateTime.UtcNow, null)).TotalCollected > 0);
        var analysis = await agent.AnalyzeAsync(staffActor, new BillingAnalysisRequest("full"));
        Assert.True(analysis.Success, analysis.Error);
        Assert.Contains(analysis.Value!.Anomalies, a => a.Type == "excessive_discount");
        var pending = await agent.GetWorkflowsAsync(tenantId, "approval", "Pending", 50);
        Assert.NotEmpty(pending);
        Assert.True((await approvals.ApproveAsync(tenantId, pending.First(p => p.ActionType == "cancel_subscription_with_refund").Id, staff.Id, Roles.Admin)).Success);
        var run = await BillingAutomationService.RunOnceAsync(db, messenger.Object, DateTime.UtcNow);
        Assert.True(run.MarkedOverdue + run.Renewed + run.Expired + run.RemindersSent >= 0);

        // Settings, forms, templates
        Assert.True((await settings.UpsertCommissionRuleAsync(tenantId, null, new UpsertCommissionRuleRequest("Agent", "Percentage", 3m, Role: "Agent"))).Success);
        Assert.Single((await settings.CalculateCommissionSplitAsync(tenantId, new CommissionSplitRequest(100000m))).Value!.Lines);
        using var layout = System.Text.Json.JsonDocument.Parse("""[{"id":"h","type":"header"},{"id":"i","type":"items"}]""");
        Assert.True((await settings.UpsertTemplateAsync(tenantId, null, new UpsertInvoiceTemplateRequest("Default", layout.RootElement.Clone()))).Success);
        using var schema = System.Text.Json.JsonDocument.Parse("""{"type":"object","properties":{"table":{"type":"integer"}},"required":["table"]}""");
        Assert.True((await forms.UpsertFormAsync(tenantId, "table-bill", new UpsertDynamicFormRequest(schema.RootElement.Clone()))).Success);
        Assert.Single(await forms.GetFormsAsync(tenantId));
        Assert.True((await billing.GetReceiptPdfAsync(adminActor, inv.Id)).Success);
    }
}
