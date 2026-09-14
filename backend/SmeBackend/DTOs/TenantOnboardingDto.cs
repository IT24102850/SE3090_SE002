using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

public class TenantOnboardingDto
{
    [Required]
    public string BusinessName { get; set; } = string.Empty;
    
    [Required]
    public string BusinessType { get; set; } = string.Empty; // Clinic, Restaurant, Gym, School, RealEstate, Tourism, General

    // Finer-grained category within BusinessType - currently only used when
    // BusinessType == "Tourism" (e.g. "Accommodation", "Water sports / diving").
    public string? SubType { get; set; }

    public string? Address { get; set; }
    public string? Phone { get; set; }
    
    [Required, EmailAddress]
    public string AdminEmail { get; set; } = string.Empty;
    
    [Required, MinLength(6)]
    public string AdminPassword { get; set; } = string.Empty;
    
    [Required]
    public string AdminFullName { get; set; } = string.Empty;
    
    public string? AdminPhone { get; set; }
    
    public string? LogoUrl { get; set; }
}