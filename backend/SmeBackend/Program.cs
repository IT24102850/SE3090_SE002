using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Middleware;
using SmeBackend.Models;
using SmeBackend.Services;

var builder = WebApplication.CreateBuilder(args);

// Railway (and most PaaS hosts) assign the listen port via $PORT at runtime
// rather than appsettings/launchSettings - bind to it when present so the
// container isn't unreachable. Local dev is unaffected (PORT is unset).
var railwayPort = Environment.GetEnvironmentVariable("PORT");
if (!string.IsNullOrEmpty(railwayPort))
{
    builder.WebHost.UseUrls($"http://0.0.0.0:{railwayPort}");
}

// Add services
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddHealthChecks();

// Swagger with JWT auth support
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Unify API", Version = "v1" });

    var xmlPath = Path.Combine(AppContext.BaseDirectory, "SmeBackend.xml");
    if (File.Exists(xmlPath)) c.IncludeXmlComments(xmlPath);

    // Add JWT Authentication to Swagger
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header using the Bearer scheme. Example: \"Bearer {token}\"",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

// PostgreSQL
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// JWT Authentication
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]!)),
            ClockSkew = TimeSpan.Zero
        };
    });

// Authorization
builder.Services.AddAuthorization(options =>
{
    // Policy for Admin only
    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("Admin"));

    // Manager and above
    options.AddPolicy("ManagerPlus", policy =>
        policy.RequireRole("Admin", "Manager"));

    // Staff and above
    options.AddPolicy("StaffPlus", policy =>
        policy.RequireRole("Admin", "Manager", "Staff"));

    // Customer and above
    options.AddPolicy("CustomerPlus", policy =>
        policy.RequireRole("Admin", "Manager", "Staff", "Customer"));

    // Inventory module's branch-scoped resource policies (InventoryRead,
    // InventoryWrite, PurchaseOrderRead, PurchaseOrderWrite).
    InventoryAuthorizationPolicies.AddInventoryPolicies(options);
});
builder.Services.AddSingleton<IAuthorizationHandler, InventoryAccessHandler>();

// Custom services
builder.Services.AddScoped<IJwtService, JwtService>();
builder.Services.AddScoped<ITenantService, TenantService>();
builder.Services.AddScoped<ITenantContext, TenantContext>();
builder.Services.AddHostedService<SmeBackend.Services.ReminderDispatchService>();
builder.Services.AddHttpClient<SmeBackend.Services.IPlannerAgentService, SmeBackend.Services.PlannerAgentService>();
builder.Services.AddScoped<SmeBackend.Services.IReminderChannelSender, SmeBackend.Services.StubReminderChannelSender>();
builder.Services.AddHttpClient<SmeBackend.Services.IPushNotificationSender, SmeBackend.Services.FcmPushNotificationSender>();
builder.Services.AddScoped<SmeBackend.Services.ICloudinaryImageService, SmeBackend.Services.CloudinaryImageService>();

// CORS
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
// Railway and other managed hosts terminate TLS at a reverse proxy. Honor its
// forwarded scheme before applying HTTPS redirection.
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

// Swagger stays on in every environment (not just Development) - the
// assignment spec requires a working deployed Swagger URL for grading.
app.UseSwagger();
app.UseSwaggerUI();

app.UseCors("AllowFrontend");

// Locally the Flutter web app and the Vite dev server both call the plain
// HTTP endpoint; redirecting them to the HTTPS port makes the browser drop
// the Origin header on the redirected request, which then fails CORS. In
// Development, serve HTTP as-is - hosted environments still get the redirect.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseAuthentication();
app.UseMiddleware<TenantResolutionMiddleware>();
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

// Auto-run migrations
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
    await db.Users.IgnoreQueryFilters()
        .Where(user => user.Email == "admin@sme-demo.local")
        .ExecuteDeleteAsync();

    if (app.Environment.IsDevelopment())
    {
        var seedTenant = await db.Tenants
            .IgnoreQueryFilters()
            .Where(tenant => tenant.Name == "SME Demo Store")
            .Select(tenant => new { tenant.Id })
            .SingleOrDefaultAsync();

        if (seedTenant is not null && !await db.Sales.IgnoreQueryFilters().AnyAsync(sale => sale.TenantId == seedTenant.Id))
        {
            scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(seedTenant.Id);
            var seedBranch = await db.Branches
                .IgnoreQueryFilters()
                .Where(branch => branch.TenantId == seedTenant.Id && branch.IsActive)
                .OrderBy(branch => branch.CreatedAt)
                .Select(branch => new { branch.Id })
                .FirstOrDefaultAsync();

            if (seedBranch is not null)
            {
                var now = DateTime.UtcNow;
                db.Sales.AddRange(
                    new Sale { TenantId = seedTenant.Id, BranchId = seedBranch.Id, OccurredAt = now.AddDays(-2), Amount = 42500m, Reference = "SALE-DEMO-001" },
                    new Sale { TenantId = seedTenant.Id, BranchId = seedBranch.Id, OccurredAt = now.AddDays(-1), Amount = 58750m, Reference = "SALE-DEMO-002" },
                    new Sale { TenantId = seedTenant.Id, BranchId = seedBranch.Id, OccurredAt = now.AddHours(-4), Amount = 31600m, Reference = "SALE-DEMO-003" });
                await db.SaveChangesAsync();
            }
        }
    }
}

app.Run();
