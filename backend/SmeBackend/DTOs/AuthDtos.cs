using System.ComponentModel.DataAnnotations;
using SmeBackend.Models;

namespace SmeBackend.DTOs;

public class RegisterDto
{
    [Required, EmailAddress]
    public string Email { get; set; } = string.Empty;
    
    [Required, MinLength(6)]
    public string Password { get; set; } = string.Empty;
    
    [Required]
    public string FullName { get; set; } = string.Empty;
    
    public string Phone { get; set; } = string.Empty;
    
    [Required]
    public Guid TenantId { get; set; }
    
    public Guid? BranchId { get; set; }

    // No Role field: this is the public customer self-registration endpoint
    // (POST /api/auth/register). Every account it creates is a Customer —
    // Staff/Manager accounts are created by an Admin via
    // POST /api/tenant/staff, which is [Authorize]-gated. Accepting a
    // client-supplied Role here would let anyone self-elevate.
}

public class UpdateProfileDto
{
    public string? FullName { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? InsuranceProvider { get; set; }
    public string? InsuranceNumber { get; set; }
    public string? MedicalNotes { get; set; }
}

public class LoginDto
{
    [Required, EmailAddress]
    public string Email { get; set; } = string.Empty;
    
    [Required]
    public string Password { get; set; } = string.Empty;
}

public class AuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public UserResponseDto User { get; set; } = null!;
}

public class UserResponseDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public Guid TenantId { get; set; }
    public Guid? BranchId { get; set; }
    public string? Address { get; set; }
    public string? InsuranceProvider { get; set; }
    public string? InsuranceNumber { get; set; }
    public string? MedicalNotes { get; set; }
}