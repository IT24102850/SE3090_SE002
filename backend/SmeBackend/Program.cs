using Microsoft.AspNetCore.RateLimiting;
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

// The Windows Event Log provider can be injected by local tooling. It requires
// elevated permissions and turns otherwise harmless EF Core warnings into a
// startup crash for a normal developer account. Development logs belong in the
// console/debug output instead.
if (builder.Environment.IsDevelopment())
{
    builder.Logging.ClearProviders();
    builder.Logging.AddSimpleConsole();
    builder.Logging.AddDebug();
}

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

// Open-Meteo: no API key, so the forecast works from a clean clone. A short
// timeout keeps an advisory call from holding up the screen that asked for it.
builder.Services.AddHttpClient(SmeBackend.Services.OpenMeteoForecastService.ClientName,
    client => client.Timeout = TimeSpan.FromSeconds(8));
builder.Services.AddScoped<SmeBackend.Services.IWeatherForecastService,
    SmeBackend.Services.OpenMeteoForecastService>();

// Live notifications. The stream is a singleton because connections outlive
// any one request; the interceptor publishes a Notification row the moment its
// transaction commits, so every site that raises one is covered without having
// to remember to announce it.
builder.Services.AddSingleton<SmeBackend.Services.INotificationStream, SmeBackend.Services.NotificationStream>();
builder.Services.AddSingleton<SmeBackend.Services.NotificationPublishInterceptor>();

// PostgreSQL
builder.Services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection"))
           .AddInterceptors(sp.GetRequiredService<SmeBackend.Services.NotificationPublishInterceptor>()));

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

    // The platform owner's console: SuperAdmin role + MFA-minted token +
    // a live server-side session (Authorization/PlatformOwnerPolicy.cs).
    PlatformOwnerPolicy.Add(options);
});
builder.Services.AddSingleton<IAuthorizationHandler, InventoryAccessHandler>();
builder.Services.AddScoped<IAuthorizationHandler, PlatformSessionHandler>();
builder.Services.AddSingleton<IPlatformSecretProtector, PlatformSecretProtector>();

// Custom services
builder.Services.AddScoped<IJwtService, JwtService>();
builder.Services.AddScoped<ITenantService, TenantService>();
builder.Services.AddScoped<ITenantContext, TenantContext>();
builder.Services.AddScoped<ICustomerAccountService, CustomerAccountService>();
builder.Services.AddHostedService<SmeBackend.Services.ReminderDispatchService>();
builder.Services.AddHttpClient<SmeBackend.Services.IPlannerAgentService, SmeBackend.Services.PlannerAgentService>();
builder.Services.AddHttpClient<SmeBackend.Services.IInventoryAgentService, SmeBackend.Services.InventoryAgentService>();
builder.Services.AddScoped<SmeBackend.Services.IReminderChannelSender, SmeBackend.Services.StubReminderChannelSender>();
builder.Services.AddHttpClient<SmeBackend.Services.IPushNotificationSender, SmeBackend.Services.FcmPushNotificationSender>();
builder.Services.AddScoped<SmeBackend.Services.ICloudinaryImageService, SmeBackend.Services.CloudinaryImageService>();
// Billing & payments engine (component 3). Integrations (Stripe, PayPal,
// SendGrid, Twilio) share one named HttpClient; each falls back to an honest
// "simulated" result when its credentials are not configured.
builder.Services.AddHttpClient(SmeBackend.Services.Billing.BillingHttp.ClientName, client =>
{
    client.Timeout = TimeSpan.FromSeconds(20);
});
builder.Services.AddScoped<SmeBackend.Services.Billing.IBillingApprovalService, SmeBackend.Services.Billing.BillingApprovalService>();
builder.Services.AddScoped<SmeBackend.Services.Billing.IBillingMessenger, SmeBackend.Services.Billing.BillingMessenger>();
builder.Services.AddScoped<IBillingService, BillingService>();
builder.Services.AddScoped<IDynamicFormService, DynamicFormService>();
builder.Services.AddScoped<SmeBackend.Services.Billing.BillingSettingsService>();
builder.Services.AddScoped<SmeBackend.Services.Billing.IBillingSettingsService>(sp =>
    sp.GetRequiredService<SmeBackend.Services.Billing.BillingSettingsService>());
builder.Services.AddScoped<SmeBackend.Services.Billing.IBillingReportService, SmeBackend.Services.Billing.BillingReportService>();
builder.Services.AddScoped<SmeBackend.Services.Billing.IBillingAgentService, SmeBackend.Services.Billing.BillingAgentService>();
// The billing copilot's two model edges (POST /billing/plan, /billing/narrate
// on the agent service). The deterministic /analyze path does not depend on
// it, so a missing agent service degrades the copilot alone.
builder.Services.AddHttpClient<SmeBackend.Services.Billing.IBillingPlannerService, SmeBackend.Services.Billing.BillingPlannerService>();
builder.Services.AddScoped<SmeBackend.Services.Billing.IPaymentCheckoutService, SmeBackend.Services.Billing.PaymentCheckoutService>();
builder.Services.AddSingleton<SmeBackend.Services.Billing.IPaymentProcessor, SmeBackend.Services.Billing.StripePaymentProcessor>();
builder.Services.AddSingleton<SmeBackend.Services.Billing.IPaymentProcessor, SmeBackend.Services.Billing.PayPalPaymentProcessor>();
builder.Services.AddSingleton<SmeBackend.Services.Billing.IPaymentProcessor, SmeBackend.Services.Billing.ManualPaymentProcessor>();
builder.Services.AddSingleton<SmeBackend.Services.Billing.IPaymentProcessorFactory, SmeBackend.Services.Billing.PaymentProcessorFactory>();
builder.Services.AddHostedService<SmeBackend.Services.Billing.BillingAutomationService>();

// The public website booking widget is anonymous, so it gets a per-IP
// budget that no signed-in endpoint needs: enough for a family working
// through the form, far short of a script hammering it.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    // Platform console sign-in: five tries a minute per address, on top of
    // the per-account lockout. An online guess of a 14+ character password
    // and a 6-digit code is not happening at 5/min.
    options.AddPolicy(SmeBackend.Controllers.PlatformAuthController.LoginRateLimitPolicy, context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));
    options.AddPolicy(SmeBackend.Controllers.PublicBookingController.RateLimitPolicy, context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));
});

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

app.UseRateLimiter();
// Nothing the platform console returns may be cached or framed: every
// response under /api/platform is no-store and carries the usual hardening
// headers, whatever proxy sits in front.
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/api/platform"))
    {
        context.Response.Headers.CacheControl = "no-store, max-age=0";
        context.Response.Headers.Pragma = "no-cache";
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["X-Frame-Options"] = "DENY";
        context.Response.Headers["Referrer-Policy"] = "no-referrer";
    }
    await next();
});
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

    // The platform owner exists in every environment - the console is for
    // the deployed site. See Data/PlatformOwnerSeeder.cs for the config keys.
    await PlatformOwnerSeeder.SeedAsync(
        db,
        app.Configuration,
        scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("PlatformOwnerSeeder"));

    if (app.Environment.IsDevelopment())
    {
        var tenantContext = scope.ServiceProvider.GetRequiredService<ITenantContext>();
        await DevelopmentUserSeeder.SeedAsync(db, tenantContext);

        var seedTenant = await db.Tenants
            .IgnoreQueryFilters()
            .Where(tenant => tenant.Name == "SME Demo Store")
            .OrderBy(tenant => tenant.CreatedAt)
            .Select(tenant => new { tenant.Id })
            .FirstOrDefaultAsync();

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
