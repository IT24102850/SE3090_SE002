using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.Billing;
using SmeBackend.Shared;

namespace SmeBackend.Tests.Billing;

/// One tenant with an Admin, a Manager, a Staff member and two customers,
/// wired to the real billing services over an in-memory database. The
/// messenger is a Moq mock, so tests can assert on what would be sent.
public sealed class BillingTestFixture
{
    public Guid TenantId { get; } = Guid.NewGuid();
    public AppDbContext Db { get; }
    public User Admin { get; }
    public User Manager { get; }
    public User Staff { get; }
    public User Customer { get; }
    public User OtherCustomer { get; }
    public Mock<IBillingMessenger> Messenger { get; } = new();
    public BillingApprovalService Approvals { get; }
    public BillingService Billing { get; }
    public BillingSettingsService Settings { get; }
    public BillingReportService Reports { get; }
    public BillingAgentService Agent { get; }
    public PaymentCheckoutService Checkout { get; }

    public BillingTestFixture()
    {
        Db = TestHelpers.NewInMemoryDb(TenantId);
        Db.Tenants.Add(new Tenant { Id = TenantId, Name = "Smile Dental", BusinessType = "Clinic", IsActive = true });

        Admin = NewUser("admin@smile.lk", "Asha Admin", UserRole.Admin);
        Manager = NewUser("manager@smile.lk", "Mahesh Manager", UserRole.Manager);
        Staff = NewUser("desk@smile.lk", "Dilini Desk", UserRole.Staff);
        Customer = NewUser("nimal@example.com", "Nimal Perera", UserRole.Customer);
        Customer.Phone = "+94771234567";
        Customer.InsuranceProvider = "Ceylinco";
        Customer.InsuranceNumber = "CEY-2026-00417";
        OtherCustomer = NewUser("kamala@example.com", "Kamala Silva", UserRole.Customer);
        Db.SaveChanges();

        Messenger.Setup(m => m.SendEmailAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<EmailAttachment?>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((string to, string _, string _, EmailAttachment? _, CancellationToken _) =>
                new MessageDeliveryResponse("Email", to, true, false, "msg-1", null));
        Messenger.Setup(m => m.SendTextAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((string channel, string to, string _, CancellationToken _) =>
                new MessageDeliveryResponse(channel, to, true, false, "SM1", null));

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Jwt:Key"] = "test-signing-key-that-is-long-enough-123456" })
            .Build();
        var processors = new PaymentProcessorFactory(new IPaymentProcessor[]
        {
            new ManualPaymentProcessor(),
            new StripePaymentProcessor(new Mock<IHttpClientFactory>().Object),
        });

        Approvals = new BillingApprovalService(Db);
        Billing = new BillingService(Db, Approvals, Messenger.Object);
        Settings = new BillingSettingsService(Db, new PlatformSecretProtector(config), processors);
        Reports = new BillingReportService(Db);
        Agent = new BillingAgentService(Db, Approvals);
        Checkout = new PaymentCheckoutService(Db, processors, Settings, Billing, NullLogger<PaymentCheckoutService>.Instance);
    }

    private User NewUser(string email, string name, UserRole role)
    {
        var user = new User { TenantId = TenantId, Email = email, FullName = name, Role = role, PasswordHash = "x" };
        Db.Users.Add(user);
        return user;
    }

    public BillingActor As(User user) => new(TenantId, user.Id, user.Role switch
    {
        UserRole.Admin => Roles.Admin,
        UserRole.Manager => Roles.Manager,
        UserRole.Staff => Roles.Staff,
        _ => Roles.Customer,
    });

    public BillingActor AdminActor => As(Admin);
    public BillingActor ManagerActor => As(Manager);
    public BillingActor StaffActor => As(Staff);
    public BillingActor CustomerActor => As(Customer);

    public static CreateInvoiceRequest InvoiceRequest(Guid customerId, decimal unitPrice = 1000m, int qty = 1,
        decimal discount = 0, decimal tax = 0, DateTime? due = null, decimal? discountPercent = null, decimal? taxRatePercent = null) =>
        new(customerId, null, null, due ?? DateTime.UtcNow.AddDays(14), "LKR", discount, tax,
            new List<CreateInvoiceItemRequest> { new("Dental check-up", qty, unitPrice, "Treatment") },
            DiscountPercent: discountPercent, TaxRatePercent: taxRatePercent);

    public async Task<InvoiceResponse> CreateInvoiceAsync(decimal unitPrice = 1000m, int qty = 1, decimal discount = 0,
        decimal tax = 0, DateTime? due = null, User? customer = null)
    {
        var result = await Billing.CreateInvoiceAsync(StaffActor, InvoiceRequest((customer ?? Customer).Id, unitPrice, qty, discount, tax, due));
        Assert.True(result.Success, result.Error);
        return result.Value!;
    }
}
