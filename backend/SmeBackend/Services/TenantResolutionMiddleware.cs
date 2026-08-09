namespace SmeBackend.Middleware;

public class TenantResolutionMiddleware
{
    private readonly RequestDelegate _next;
    
    public TenantResolutionMiddleware(RequestDelegate next)
    {
        _next = next;
    }
    
    public async Task InvokeAsync(HttpContext context)
    {
        if (context.User.Identity?.IsAuthenticated == true)
        {
            var tenantIdClaim = context.User.FindFirst("tenantId")?.Value;
            var roleClaim = context.User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
            var branchIdClaim = context.User.FindFirst("branchId")?.Value;
            
            if (!string.IsNullOrEmpty(tenantIdClaim))
                context.Items["TenantId"] = Guid.Parse(tenantIdClaim);
            
            if (!string.IsNullOrEmpty(roleClaim))
                context.Items["UserRole"] = roleClaim;
                
            if (!string.IsNullOrEmpty(branchIdClaim))
                context.Items["BranchId"] = Guid.Parse(branchIdClaim);
        }
        
        await _next(context);
    }
}