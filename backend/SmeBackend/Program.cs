using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Middleware;
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

// Swagger with JWT auth support
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "SME Platform API", Version = "v1" });

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
// Swagger stays on in every environment (not just Development) - the
// assignment spec requires a working deployed Swagger URL for grading.
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.UseCors("AllowFrontend");

app.UseAuthentication();
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous();

app.MapControllers();

// Auto-run migrations
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
