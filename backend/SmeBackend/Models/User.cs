namespace SmeBackend.Models;

public class User : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public Guid? BranchId { get; set; }
    public Branch? Branch { get; set; }
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Customer;
    public bool IsActive { get; set; } = true;

    // Global customer accounts (Services/CustomerAccountService.cs).
    //
    // A customer signs up once, with no business, and gets one *identity*
    // row in the hidden "Unify Customers" tenant. The first time they book
    // with (or open) a business, a *membership* row is created in that
    // business's tenant - an ordinary Customer user as far as every
    // dashboard, report and booking is concerned - with LinkedAccountId
    // pointing back at the identity. Only identity rows can sign in; a
    // membership's token is minted by POST /api/auth/join/{tenantId}.
    // Null on every non-customer row and on legacy per-business customers.
    public Guid? LinkedAccountId { get; set; }

    // Self-service avatar, set via PUT /api/auth/me after an upload through
    // MediaController (purpose="avatar") - same "upload, then attach the
    // URL" split as Tenant.LogoUrl/CoverImageUrl.
    public string? ProfilePictureUrl { get; set; }

    // FR-C2: self-service profile details (contact + medical/insurance).
    public string? Address { get; set; }
    public string? InsuranceProvider { get; set; }
    public string? InsuranceNumber { get; set; }
    public string? MedicalNotes { get; set; }
    public bool IsApproved { get; set; } = true;

    // Optional demographics for the gym dashboard's member breakdown (age
    // band, gender). Nullable and self-declared; a blank stays blank and
    // the report buckets it as "Not stated".
    public DateTime? DateOfBirth { get; set; }
    public string? Gender { get; set; }
}