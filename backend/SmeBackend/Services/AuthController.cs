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
        // Login happens before a tenant is known, so tenant query filters
        // cannot be applied until the user's tenant has been resolved.
        //
        // Email is not unique across tenants (users has no global email
        // index; the seed scripts and onboarding both create an admin per
        // tenant with whatever email they are given), so the same address
        // can name an account in several tenants. Taking the first row meant
        // a demo tenant seeded with someone's email shadowed their real
        // account: they could never sign in, because only the demo copy's
        // password was ever checked. The password is the disambiguator - it
        // is checked against every account carrying the email, and the one
        // it matches is the one they meant.
        var candidates = await _context.Users
            .IgnoreQueryFilters()
            .Include(u => u.Tenant)
            .Where(u => u.Email == dto.Email && u.IsActive)
            .OrderByDescending(u => u.CreatedAt)
            .ToListAsync();

        var user = candidates.FirstOrDefault(u => BCrypt.Net.BCrypt.Verify(dto.Password, u.PasswordHash));
        if (user == null)
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
        // An empty string is the clients' "remove my photo" signal (a plain
        // null means "leave it alone", like every other field here).
        if (dto.ProfilePictureUrl != null)
            user.ProfilePictureUrl = string.IsNullOrWhiteSpace(dto.ProfilePictureUrl) ? null : dto.ProfilePictureUrl;
        user.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();
        return Ok(MapToUserDto(user));
    }

    /// <summary>Changes the signed-in user's password. Requires the current one, so a stolen token alone cannot lock the owner out.</summary>
    [HttpPost("change-password")]
    [Authorize]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordDto dto)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (userId == null) return Unauthorized();

        var user = await _context.Users.FindAsync(Guid.Parse(userId));
        if (user == null) return NotFound();

        if (!BCrypt.Net.BCrypt.Verify(dto.CurrentPassword, user.PasswordHash))
            return BadRequest(new { message = "Current password is incorrect." });
        if (dto.NewPassword == dto.CurrentPassword)
            return BadRequest(new { message = "New password must be different from the current one." });

        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.NewPassword);
        user.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return Ok(new { message = "Password changed." });
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
        MedicalNotes = user.MedicalNotes,
        ProfilePictureUrl = user.ProfilePictureUrl
    };
}