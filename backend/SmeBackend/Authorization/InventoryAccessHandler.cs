using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using SmeBackend.Models;

namespace SmeBackend.Authorization;

public sealed class InventoryAccessHandler : AuthorizationHandler<InventoryAccessRequirement, InventoryAccessResource>
{
    public const string TenantIdClaimType = "tenant_id";
    public const string BranchIdClaimType = "branch_id";
    public const string ComponentClaimType = "component";

    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        InventoryAccessRequirement requirement,
        InventoryAccessResource resource)
    {
        var tenantId = context.User.FindFirst(TenantIdClaimType)?.Value;
        if (!Guid.TryParse(tenantId, out var callerTenantId) || callerTenantId != resource.TenantId)
        {
            return Task.CompletedTask;
        }

        // Admins have full access within their tenant.
        if (context.User.IsInRole(UserRole.Admin.ToString()))
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Managers may act only on resources assigned to their JWT branch.
        if (context.User.IsInRole(UserRole.Manager.ToString()) &&
            resource.BranchId.HasValue &&
            Guid.TryParse(context.User.FindFirst(BranchIdClaimType)?.Value, out var managerBranchId) &&
            managerBranchId == resource.BranchId.Value)
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Staff require an explicit component grant. A '*' grant is reserved for
        // trusted internal staff provisioning, not ordinary role assignment.
        if (context.User.IsInRole(UserRole.Staff.ToString()) &&
            context.User.FindAll(ComponentClaimType)
                .Any(claim => claim.Value is "*" || claim.Value == requirement.Component))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
