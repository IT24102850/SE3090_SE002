using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace SmeBackend.Authorization
{
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public class TenantAuthorizeAttribute : AuthorizeAttribute, IAsyncAuthorizationFilter
    {
        private readonly string[] _allowedRoles;

        public TenantAuthorizeAttribute(params string[] roles)
        {
            _allowedRoles = roles;
            if (roles.Length > 0)
            {
                Roles = string.Join(",", roles);
            }
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            var user = context.HttpContext.User;

            if (!user.Identity?.IsAuthenticated ?? true)
            {
                context.Result = new UnauthorizedResult();
                return;
            }

            // Check role
            if (_allowedRoles.Length > 0 && !_allowedRoles.Any(r => user.IsInRole(r)))
            {
                context.Result = new ForbidResult();
                return;
            }

            // Extract tenantId from claim and validate
            var tenantClaim = user.FindFirst("tenantId")?.Value;
            if (string.IsNullOrEmpty(tenantClaim) || !Guid.TryParse(tenantClaim, out var tenantId))
            {
                context.Result = new UnauthorizedObjectResult(new { error = "Tenant context missing or invalid" });
                return;
            }

            // Store tenantId in HttpContext.Items for downstream use
            context.HttpContext.Items["TenantId"] = tenantId;
        }
    }
}