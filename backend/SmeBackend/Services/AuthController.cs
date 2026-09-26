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
    private readonly ICustomerAccountService _customers;

    public AuthController(AppDbContext context, IJwtService jwtService, ICustomerAccountService customers)
    {
        _context = context;
        _jwtService = jwtService;
        _customers = customers;
    }

    // Public customer self-registration. Creates one global customer
    // account (Services/CustomerAccountService.cs); TenantId is optional and,
    // when given, also joins that business straight away so the token that
    // comes back is already scoped to it. Role is never client-supplied
    // (see RegisterDto) — Customer is the only role this can ever create.
    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> Register([FromBody] RegisterDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();

        if (dto.TenantId is { } tenantId)
        {
            var tenant = await _context.Tenants.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId);
            if (tenant == null || !tenant.IsActive || CustomerAccountService.IsReserved(tenant.BusinessType))
                return BadRequest(new { message = "This business is not available for sign-up." });
        }

        // One sign-in per email: any account that can log in with it (an
        // identity, a legacy per-business customer, or staff) blocks it.
        if (await _context.Users.IgnoreQueryFilters().AnyAsync(u => u.Email == email && u.LinkedAccountId == null))
            return BadRequest(new { message = "Email already registered" });

        var user = await _customers.RegisterAsync(email, dto.Password, dto.FullName, dto.Phone, dto.TenantId, dto.BranchId);

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
            // The platform owner signs in only through the platform console
            // (PlatformAuthController), where a TOTP code is mandatory. The
            // ordinary login never sees that account, so a leaked password
            // alone opens nothing.
            .Where(u => u.Role != UserRole.SuperAdmin)
            // Memberships never sign in; the global identity does, and
            // POST /auth/join mints per-business tokens from it.
            .Where(u => u.LinkedAccountId == null)
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

    /// <summary>
    /// Customer joins a business: returns a token scoped to that business
    /// (creating the membership on first contact), so the resource, slot and
    /// booking endpoints - which are scoped by the token's tenant - work
    /// there. Idempotent; the account's other memberships are untouched.
    /// </summary>
    [HttpPost("join/{tenantId:guid}")]
    [Authorize(Roles = "Customer")]
    public async Task<ActionResult<AuthResponseDto>> JoinBusiness(Guid tenantId)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (userId == null) return Unauthorized();

        var membership = await _customers.JoinAsync(Guid.Parse(userId), tenantId);
        if (membership == null)
            return BadRequest(new { message = "This business is not available." });

        return Ok(new AuthResponseDto
        {
            AccessToken = _jwtService.GenerateAccessToken(membership),
            RefreshToken = _jwtService.GenerateRefreshToken(),
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(membership)
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
        // A customer is one person across every business they have joined;
        // the identity and the other memberships get the same change.
        if (user.Role == UserRole.Customer)
            await _customers.PropagateProfileAsync(user.Id, user);
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
        // The identity is what signs in, so it must carry the new hash too.
        if (user.Role == UserRole.Customer)
            await _customers.PropagatePasswordAsync(user.Id, user.PasswordHash);

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