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

    // Self-service avatar, set via PUT /api/auth/me after an upload through
    // MediaController (purpose="avatar") - same "upload, then attach the
    // URL" split as Tenant.LogoUrl/CoverImageUrl.
    public string? ProfilePictureUrl { get; set; }

    // FR-C2: self-service profile details (contact + medical/insurance).
    public string? Address { get; set; }
    public string? InsuranceProvider { get; set; }
    public string? InsuranceNumber { get; set; }
    public string? MedicalNotes { get; set; }
}