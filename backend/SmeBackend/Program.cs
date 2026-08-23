using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using System.Security.Claims;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Tenancy;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks();

var jwtSettings = builder.Configuration.GetSection("Jwt");
var jwtKey = jwtSettings["Key"]
    ?? throw new InvalidOperationException("JWT signing key is not configured. Set Jwt__Key through user secrets or an environment variable.");

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtSettings["Issuer"],
            ValidateAudience = true,
            ValidAudience = jwtSettings["Audience"],
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            NameClaimType = ClaimTypes.NameIdentifier,
            RoleClaimType = ClaimTypes.Role,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization(InventoryAuthorizationPolicies.AddInventoryPolicies);
builder.Services.AddSingleton<IAuthorizationHandler, InventoryAccessHandler>();
builder.Services.AddScoped<ITenantContext, TenantContext>();

// Add PostgreSQL
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var app = builder.Build();

// Middleware pipeline
// Railway and other managed hosts terminate TLS at a reverse proxy.  Honor its
// forwarded scheme before applying HTTPS redirection.
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

// Keep the OpenAPI document available on the shared deployment for acceptance
// testing and client integration. The API remains protected by its endpoint
// authorization policies; Swagger only describes those endpoints.
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.UseCors("AllowFrontend");
app.UseAuthentication();
app.UseMiddleware<TenantContextMiddleware>();
app.UseAuthorization();
app.MapHealthChecks("/health/live");
app.MapGet("/health", async (AppDbContext db, CancellationToken cancellationToken) =>
{
    var databaseReachable = await db.Database.CanConnectAsync(cancellationToken);

    return databaseReachable
        ? Results.Ok(new { status = "Healthy", database = "Healthy" })
        : Results.Json(
            new { status = "Unhealthy", database = "Unavailable" },
            statusCode: StatusCodes.Status503ServiceUnavailable);
}).AllowAnonymous();
app.MapControllers();

// Auto-run migrations on startup
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
    if (app.Environment.IsDevelopment())
    {
        var tenantContext = scope.ServiceProvider.GetRequiredService<ITenantContext>();
        await DevelopmentUserSeeder.SeedAsync(db, tenantContext);
    }
}

app.Run();
