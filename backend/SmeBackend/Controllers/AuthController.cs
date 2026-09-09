using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Tenancy;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController(AppDbContext db, IConfiguration configuration, ITenantContext tenantContext) : ControllerBase
{
    [HttpPost("login")]
    public async Task<ActionResult<LoginResponse>> Login(LoginRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var user = await db.Users.IgnoreQueryFilters()
            .SingleOrDefaultAsync(candidate => candidate.Email == email && candidate.Tenant.IsActive);

        if (user is null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            return Unauthorized(new { message = "Invalid email or password." });
        }
        if (!user.IsApproved)
        {
            return Unauthorized(new { message = "Your signup request is pending Admin approval. Please try again a little later." });
        }

        var key = configuration["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(key))
        {
            return Problem("JWT signing key is not configured.", statusCode: StatusCodes.Status500InternalServerError);
        }

        return Ok(new LoginResponse(CreateToken(user, key)));
    }

    [HttpPost("signup")]
    public async Task<ActionResult<SignupResponse>> Signup(SignupRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(email) ||
            string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8 ||
            string.IsNullOrWhiteSpace(request.BusinessName))
        {
            return BadRequest(new { message = "Name, business name, email, and a password of at least 8 characters are required." });
        }

        if (await db.Users.IgnoreQueryFilters().AnyAsync(candidate => candidate.Email == email))
        {
            return Conflict(new { message = "An account with this email already exists." });
        }

        var tenant = new Tenant { Name = request.BusinessName.Trim(), BusinessType = "Retail" };
        var branch = new Branch
        {
            TenantId = tenant.Id,
            Tenant = tenant,
            Name = "Main Branch",
            Address = string.Empty,
            Phone = string.Empty,
        };
        var user = new User
        {
            TenantId = tenant.Id,
            Tenant = tenant,
            BranchId = branch.Id,
            Branch = branch,
            Email = email,
            FullName = request.FullName.Trim(),
            Phone = request.Phone?.Trim() ?? string.Empty,
            Role = UserRole.Admin,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            IsApproved = false,
        };

        tenantContext.SetTenant(tenant.Id);
        db.Tenants.Add(tenant);
        db.Branches.Add(branch);
        db.Users.Add(user);
        await db.SaveChangesAsync();

        return Accepted(new SignupResponse("Signup request submitted. An Admin must approve your account and assign a role before you can sign in."));
    }

    private string CreateToken(User user, string key)
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim("tenant_id", user.TenantId.ToString()),
        }
        .Concat(user.BranchId.HasValue
            ? new[] { new Claim("branch_id", user.BranchId.Value.ToString()) }
            : Array.Empty<Claim>())
        .Concat(user.Role == UserRole.Staff
            ? new[] { new Claim("component", "inventory.read"), new Claim("component", "inventory.write") }
            : Array.Empty<Claim>())
        .ToArray();
        var credentials = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: configuration["Jwt:Issuer"],
            audience: configuration["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

public sealed record LoginRequest(string Email, string Password);
public sealed record SignupRequest(string FullName, string BusinessName, string Email, string Password, string? Phone = null);
public sealed record LoginResponse(string AccessToken);
public sealed record SignupResponse(string Message);
