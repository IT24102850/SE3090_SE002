namespace SmeBackend.Tenancy;

/// <summary>
/// Sets the request-scoped tenant from a validated JWT claim. Tenant scope is
/// never taken from a route, query string, or request body.
/// </summary>
public sealed class TenantContextMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, ITenantContext tenantContext)
    {
        var tenantIdClaim = context.User.FindFirst("tenant_id")?.Value;
        if (Guid.TryParse(tenantIdClaim, out var tenantId))
        {
            tenantContext.SetTenant(tenantId);
        }

        await next(context);
    }
}
