using SmeBackend.Services;

namespace SmeBackend.Middleware;

public class TenantResolutionMiddleware
{
    private readonly RequestDelegate _next;
    
    public TenantResolutionMiddleware(RequestDelegate next)
    {
        _next = next;
    }
    
    public async Task InvokeAsync(HttpContext context, ITenantContext tenantContext, ICurrentActor currentActor)
    {
        if (context.User.Identity?.IsAuthenticated == true)
        {
            var tenantIdClaim = context.User.FindFirst("tenantId")?.Value;
            var roleClaim = context.User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
            var branchIdClaim = context.User.FindFirst("branchId")?.Value;
            
            if (!string.IsNullOrEmpty(tenantIdClaim) && Guid.TryParse(tenantIdClaim, out var tenantId))
            {
                tenantContext.SetTenantId(tenantId);
                context.Items["TenantId"] = tenantId;
            }
            
            if (!string.IsNullOrEmpty(roleClaim))
                context.Items["UserRole"] = roleClaim;

            // Who to attribute booking history to (Data/BookingHistoryRecorder).
            var userIdClaim = context.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            currentActor.Set(Guid.TryParse(userIdClaim, out var userId) ? userId : null, roleClaim);
                
            if (!string.IsNullOrEmpty(branchIdClaim) && Guid.TryParse(branchIdClaim, out var branchId))
                context.Items["BranchId"] = branchId;
        }
        
        await _next(context);
    }
}