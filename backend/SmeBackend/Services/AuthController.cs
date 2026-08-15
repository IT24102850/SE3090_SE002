using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _context;
    private readonly IJwtService _jwtService;
    
    public AuthController(AppDbContext context, IJwtService jwtService)
    {
        _context = context;
        _jwtService = jwtService;
    }
    
    // Public customer self-registration: signs the caller up as a Customer of
    // an existing, active tenant. Role is never client-supplied (see
    // RegisterDto) — this is the only role this endpoint can ever create.
    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> Register([FromBody] RegisterDto dto)
    {
        var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Id == dto.TenantId);
        if (tenant == null || !tenant.IsActive)
            return BadRequest(new { message = "This business is not available for sign-up." });

        // Check if email exists
        if (await _context.Users.AnyAsync(u => u.Email == dto.Email))
            return BadRequest(new { message = "Email already registered" });

        // Hash password with BCrypt
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password);

        var user = new User
        {
            Email = dto.Email,
            PasswordHash = passwordHash,
            FullName = dto.FullName,
            Phone = dto.Phone,
            TenantId = dto.TenantId,
            BranchId = dto.BranchId,
            Role = UserRole.Customer
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();
        
        var token = _jwtService.GenerateAccessToken(user);
        var refreshToken = _jwtService.GenerateRefreshToken();
        
        return Ok(new AuthResponseDto
        {
            AccessToken = token,
            RefreshToken = refreshToken,
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(user)
        });
    }
    
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> Login([FromBody] LoginDto dto)
    {
        var user = await _context.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email == dto.Email && u.IsActive);
        
        if (user == null || !BCrypt.Net.BCrypt.Verify(dto.Password, user.PasswordHash))
            return Unauthorized(new { message = "Invalid email or password" });
        
        if (!user.Tenant.IsActive)
            return Unauthorized(new { message = "Tenant is inactive" });
        
        var token = _jwtService.GenerateAccessToken(user);
        var refreshToken = _jwtService.GenerateRefreshToken();
        
        return Ok(new AuthResponseDto
        {
            AccessToken = token,
            RefreshToken = refreshToken,
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(user)
        });
    }
    
    [HttpGet("me")]
    [Authorize]
    public async Task<ActionResult<UserResponseDto>> GetCurrentUser()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (userId == null) return Unauthorized();

        var user = await _context.Users.FindAsync(Guid.Parse(userId));
        if (user == null) return NotFound();

        return Ok(MapToUserDto(user));
    }

    // FR-C2: self-service profile update. Email/Role/TenantId are
    // intentionally not editable here.
    [HttpPut("me")]
    [Authorize]
    public async Task<ActionResult<UserResponseDto>> UpdateCurrentUser([FromBody] UpdateProfileDto dto)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (userId == null) return Unauthorized();

        var user = await _context.Users.FindAsync(Guid.Parse(userId));
        if (user == null) return NotFound();

        if (!string.IsNullOrWhiteSpace(dto.FullName)) user.FullName = dto.FullName;
        if (dto.Phone != null) user.Phone = dto.Phone;
        if (dto.Address != null) user.Address = dto.Address;
        if (dto.InsuranceProvider != null) user.InsuranceProvider = dto.InsuranceProvider;
        if (dto.InsuranceNumber != null) user.InsuranceNumber = dto.InsuranceNumber;
        if (dto.MedicalNotes != null) user.MedicalNotes = dto.MedicalNotes;
        user.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();
        return Ok(MapToUserDto(user));
    }

    private static UserResponseDto MapToUserDto(User user) => new()
    {
        Id = user.Id,
        Email = user.Email,
        FullName = user.FullName,
        Phone = user.Phone,
        Role = user.Role.ToString(),
        TenantId = user.TenantId,
        BranchId = user.BranchId,
        Address = user.Address,
        InsuranceProvider = user.InsuranceProvider,
        InsuranceNumber = user.InsuranceNumber,
        MedicalNotes = user.MedicalNotes
    };
}