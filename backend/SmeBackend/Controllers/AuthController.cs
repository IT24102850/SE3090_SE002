using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
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
    private readonly IPasswordResetManager _passwordReset;
    private readonly IMobileExternalAuthService _externalAuth;

    public AuthController(AppDbContext context, IJwtService jwtService, ICustomerAccountService customers, IPasswordResetManager passwordReset, IMobileExternalAuthService externalAuth)
    {
        _context = context;
        _jwtService = jwtService;
        _customers = customers;
        _passwordReset = passwordReset;
        _externalAuth = externalAuth;
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
        var refreshToken = await RefreshTokenStore.IssueAsync(_context, user.Id);

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
        return await Authenticate(dto, mobileClient: false);
    }

    [HttpPost("mobile/login")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> MobileLogin([FromBody] LoginDto dto)
    {
        if (Request.Headers.ContainsKey("Origin"))
            return StatusCode(StatusCodes.Status403Forbidden, new { message = "Mobile sign-in is not available from a web browser." });

        return await Authenticate(dto, mobileClient: true);
    }

    private async Task<ActionResult<AuthResponseDto>> Authenticate(LoginDto dto, bool mobileClient)
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

        // Merge of two independent changes, both kept:
        //   the port added a mobile-specific access token (longer lived, so a
        //   phone is not signed out between sessions),
        //   main replaced the throwaway refresh token with a persisted one
        //   (RefreshTokenStore), which is what makes revocation real.
        // Taking either alone would silently drop the other's behaviour.
        var token = mobileClient
            ? _jwtService.GenerateMobileAccessToken(user)
            : _jwtService.GenerateAccessToken(user);
        var refreshToken = await RefreshTokenStore.IssueAsync(_context, user.Id);

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
            RefreshToken = await RefreshTokenStore.IssueAsync(_context, membership.Id),
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(membership)
        });
    }

    /// <summary>
    /// Exchanges a refresh token for a new access token and a new refresh
    /// token. Each refresh token works once; replaying a used one signs the
    /// user out everywhere (see RefreshTokenStore).
    /// </summary>
    /// <response code="200">New tokens.</response>
    /// <response code="401">The refresh token is unknown, expired, revoked or reused.</response>
    [HttpPost("refresh")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponseDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AuthResponseDto>> Refresh([FromBody] RefreshRequestDto dto, CancellationToken ct)
    {
        var rotation = await RefreshTokenStore.RotateAsync(_context, dto.RefreshToken, ct);
        if (rotation is null)
            return Unauthorized(new { message = "Your session has expired. Please sign in again." });

        return Ok(new AuthResponseDto
        {
            AccessToken = _jwtService.GenerateAccessToken(rotation.User),
            RefreshToken = rotation.RefreshToken,
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(rotation.User)
        });
    }

    /// <summary>Signs out: revokes the given refresh token. Always 204, so it reveals nothing about the token.</summary>
    [HttpPost("logout")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Logout([FromBody] RefreshRequestDto dto, CancellationToken ct)
    {
        await RefreshTokenStore.RevokeAsync(_context, dto.RefreshToken, ct);
        return NoContent();
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
        // A new password ends every other session: a thief holding an old
        // refresh token cannot keep minting access tokens with it.
        await RefreshTokenStore.RevokeAllForUserAsync(_context, user.Id);

        return Ok(new { message = "Password changed." });
    }

    /// <summary>
    /// Requests a password reset email/code.
    /// </summary>
    [HttpPost("forgot-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();
        var exists = await _context.Users
            .IgnoreQueryFilters()
            .AnyAsync(u => u.Email.ToLower() == email && u.IsActive && u.Role != UserRole.SuperAdmin);

        if (exists)
        {
            await _passwordReset.GenerateResetCodeAsync(email);
        }

        return Ok(new
        {
            message = "If the address is registered and email delivery is configured, a 6-digit verification code will arrive shortly."
        });
    }

    /// <summary>
    /// Verifies a native provider token and signs in an existing account, or
    /// creates a customer account on first sign-in.
    /// </summary>
    [HttpPost("mobile/external-login")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> MobileExternalLogin(
        [FromBody] MobileExternalLoginDto dto,
        CancellationToken cancellationToken)
    {
        if (Request.Headers.ContainsKey("Origin"))
            return StatusCode(StatusCodes.Status403Forbidden, new { message = "Provider sign-in is only available in the mobile app." });

        ExternalIdentity identity;
        try
        {
            identity = await _externalAuth.GetVerifiedIdentityAsync(
                dto.Provider, dto.IdToken, dto.AccessToken, cancellationToken);
        }
        catch (ExternalAuthException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        var email = identity.Email.Trim().ToLowerInvariant();
        if (dto.TenantId is { } requestedTenantId)
        {
            var tenant = await _context.Tenants.IgnoreQueryFilters().AsNoTracking()
                .FirstOrDefaultAsync(item => item.Id == requestedTenantId, cancellationToken);
            if (tenant == null || !tenant.IsActive || CustomerAccountService.IsReserved(tenant.BusinessType))
                return BadRequest(new { message = "This business is not available for customer sign-up." });
        }
        var matches = await _context.Users
            .IgnoreQueryFilters()
            .Include(u => u.Tenant)
            .Where(u => u.Email.ToLower() == email)
            .ToListAsync(cancellationToken);

        var accountIds = matches
            .Select(user => user.LinkedAccountId ?? user.Id)
            .Distinct()
            .ToList();
        if (accountIds.Count > 1)
        {
            return Conflict(new { message = "This email belongs to more than one workspace account. Sign in with your password to choose the correct account." });
        }

        User user;
        if (accountIds.Count == 0)
        {
            var randomPassword = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
            user = await _customers.RegisterAsync(email, randomPassword, identity.DisplayName, string.Empty, dto.TenantId, null);
            user.ProfilePictureUrl = identity.PictureUrl;
            await _context.SaveChangesAsync(cancellationToken);
        }
        else
        {
            var accountId = accountIds[0];
            user = matches.FirstOrDefault(candidate => candidate.Id == accountId)
                ?? matches.First(candidate => candidate.LinkedAccountId == accountId);

            if (user.Role == UserRole.SuperAdmin || !user.IsActive || !user.Tenant.IsActive)
                return Unauthorized(new { message = "This account is unavailable for mobile sign-in." });

            if (dto.TenantId is { } tenantId && user.Role == UserRole.Customer)
            {
                var membership = await _customers.JoinAsync(user.Id, tenantId);
                if (membership == null)
                    return BadRequest(new { message = "Could not join this business with your customer account." });
                user = membership;
            }
        }

        var token = _jwtService.GenerateMobileAccessToken(user);
        return Ok(new AuthResponseDto
        {
            AccessToken = token,
            RefreshToken = _jwtService.GenerateRefreshToken(),
            ExpiresAt = DateTime.UtcNow.AddHours(2),
            User = MapToUserDto(user)
        });
    }

    /// <summary>
    /// Verifies the 6-digit reset code before showing the new-password form.
    /// The code remains valid for the final reset request.
    /// </summary>
    [HttpPost("verify-reset-code")]
    [AllowAnonymous]
    public IActionResult VerifyResetCode([FromBody] VerifyResetCodeDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();
        if (!_passwordReset.VerifyCode(email, dto.Code))
        {
            return BadRequest(new { message = "That code is incorrect or expired. Check the email and try again, or request a new code." });
        }

        return Ok(new { message = "Code verified. You can now choose a new password." });
    }

    /// <summary>
    /// Resets the password using the verified email code.
    /// </summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();
        var valid = _passwordReset.VerifyAndConsumeCode(email, dto.Code);
        if (!valid)
        {
            return BadRequest(new { message = "Invalid or expired reset code. Please request a new code." });
        }

        var users = await _context.Users
            .IgnoreQueryFilters()
            .Where(u => u.Email.ToLower() == email && u.IsActive && u.Role != UserRole.SuperAdmin)
            .ToListAsync();

        if (users.Count == 0)
        {
            return BadRequest(new { message = "Account not found." });
        }

        var newHash = BCrypt.Net.BCrypt.HashPassword(dto.NewPassword);
        foreach (var user in users)
        {
            user.PasswordHash = newHash;
            user.UpdatedAt = DateTime.UtcNow;
            if (user.Role == UserRole.Customer)
            {
                await _customers.PropagatePasswordAsync(user.Id, newHash);
            }
        }

        await _context.SaveChangesAsync();
        return Ok(new { message = "Password has been successfully reset! You can now sign in with your new credentials." });
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
