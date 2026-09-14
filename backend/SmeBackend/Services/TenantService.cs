using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using System.Text.Json;

namespace SmeBackend.Services;

public interface ITenantService
{
    Task<AuthResponseDto> OnboardTenantAsync(TenantOnboardingDto dto);
}

public class TenantService : ITenantService
{
    private readonly AppDbContext _context;
    private readonly IJwtService _jwtService;
    
    public TenantService(AppDbContext context, IJwtService jwtService)
    {
        _context = context;
        _jwtService = jwtService;
    }
    
    public async Task<AuthResponseDto> OnboardTenantAsync(TenantOnboardingDto dto)
    {
        // Use transaction — all or nothing
        await using var transaction = await _context.Database.BeginTransactionAsync();
        
        try
        {
            // 1. Create Tenant
            var tenant = new Tenant
            {
                Name = dto.BusinessName,
                BusinessType = dto.BusinessType,
                SubType = dto.SubType,
                LogoUrl = dto.LogoUrl,
                IsActive = true
            };
            
            _context.Tenants.Add(tenant);
            await _context.SaveChangesAsync();
            
            // 2. Seed default modules based on business type
            var defaultModules = GetDefaultModulesForBusinessType(dto.BusinessType);
            foreach (var moduleName in defaultModules)
            {
                _context.TenantModules.Add(new TenantModule
                {
                    TenantId = tenant.Id,
                    ModuleName = moduleName,
                    IsEnabled = true,
                    ConfigJson = GetDefaultModuleConfig(dto.BusinessType, moduleName)
                });
            }
            
            // 3. Create default branch
            var branch = new Branch
            {
                TenantId = tenant.Id,
                Name = "Main Branch",
                Address = dto.Address ?? "Not specified",
                Phone = dto.Phone ?? "Not specified",
                IsActive = true
            };
            _context.Branches.Add(branch);
            await _context.SaveChangesAsync();
            
            // 4. Create Admin user
            var passwordHash = BCrypt.Net.BCrypt.HashPassword(dto.AdminPassword);
            
            var admin = new User
            {
                TenantId = tenant.Id,
                BranchId = branch.Id,
                Email = dto.AdminEmail,
                PasswordHash = passwordHash,
                FullName = dto.AdminFullName,
                Phone = dto.AdminPhone ?? string.Empty,
                Role = UserRole.Admin,
                IsActive = true
            };
            
            _context.Users.Add(admin);
            await _context.SaveChangesAsync();
            
            // 5. Commit transaction
            await transaction.CommitAsync();
            
            // 6. Generate JWT token
            var token = _jwtService.GenerateAccessToken(admin);
            var refreshToken = _jwtService.GenerateRefreshToken();
            
            return new AuthResponseDto
            {
                AccessToken = token,
                RefreshToken = refreshToken,
                ExpiresAt = DateTime.UtcNow.AddHours(2),
                User = new UserResponseDto
                {
                    Id = admin.Id,
                    Email = admin.Email,
                    FullName = admin.FullName,
                    Role = admin.Role.ToString(),
                    TenantId = admin.TenantId,
                    BranchId = admin.BranchId
                }
            };
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }
    
    private static List<string> GetDefaultModulesForBusinessType(string businessType)
    {
        var baseModules = new List<string> { "Appointments", "Billing", "Inventory" };
        
        return businessType.ToLower() switch
        {
            "clinic" or "dental" => new List<string> { "Appointments", "Billing", "Inventory", "Prescriptions" },
            "restaurant" or "cafe" => new List<string> { "Reservations", "Billing", "Inventory", "Kitchen" },
            "gym" or "fitness" => new List<string> { "Bookings", "Billing", "Inventory", "Memberships" },
            "school" or "tuition" => new List<string> { "Scheduling", "Billing", "Inventory", "Attendance" },
            "realestate" => new List<string> { "Appointments", "Billing", "Listings" },
            "tourism" => new List<string> { "Bookings", "Billing", "Inventory", "Itinerary" },
            _ => baseModules
        };
    }
    
    private static string? GetDefaultModuleConfig(string businessType, string moduleName)
    {
        var configs = new Dictionary<string, object>();
        
        if (moduleName == "Appointments" || moduleName == "Bookings" || moduleName == "Reservations" || moduleName == "Scheduling")
        {
            configs["allowOnlineBooking"] = true;
            configs["requireApproval"] = false;
            configs["slotDurationMinutes"] = businessType.ToLower() switch
            {
                "clinic" or "dental" => 30,
                "restaurant" or "cafe" => 60,
                "gym" or "fitness" => 60,
                _ => 30
            };
        }
        
        if (moduleName == "Billing")
        {
            configs["currency"] = "LKR";
            configs["taxRate"] = 0;
            configs["allowPartialPayments"] = true;
        }
        
        return configs.Count > 0 ? JsonSerializer.Serialize(configs) : null;
    }
}