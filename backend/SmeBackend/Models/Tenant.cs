namespace SmeBackend.Models;

public class Tenant : BaseEntity
{
    public string Name { get; set; } = string.Empty;
    public string BusinessType { get; set; } = string.Empty; // Clinic, Restaurant, Gym, etc.
    public string? LogoUrl { get; set; }
    public bool IsActive { get; set; } = true;
}