using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using SmeBackend.Models;

namespace SmeBackend.Authorization;

public sealed class InventoryAccessHandler : AuthorizationHandler<InventoryAccessRequirement, InventoryAccessResource>
{
    // Matches the claim names JwtService actually issues (Services/JwtService.cs).
    public const string TenantIdClaimType = "tenantId";
    public const string BranchIdClaimType = "branchId";
    public const string ComponentClaimType = "component";
    public const string ClientPlatformClaimType = "clientPlatform";

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

        var hasAssignedBranch = Guid.TryParse(
            context.User.FindFirst(BranchIdClaimType)?.Value,
            out var assignedBranchId);

        // Branch-bound inventory and purchase-order access always has to
        // match the branch in the authenticated token. Only explicit metadata
        // policies may omit a branch; they still require a valid assignment.
        if (resource.BranchId.HasValue &&
            (!hasAssignedBranch || assignedBranchId != resource.BranchId.Value))
        {
            return Task.CompletedTask;
        }

        var branchlessMetadataAllowed =
            resource.BranchId.HasValue ||
            requirement.AllowsBranchlessMetadata && hasAssignedBranch;

        if (context.User.IsInRole(UserRole.Manager.ToString()) &&
            branchlessMetadataAllowed)
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Staff require an explicit component grant. A '*' grant is reserved for
        // trusted internal staff provisioning, not ordinary role assignment.
        if (context.User.IsInRole(UserRole.Staff.ToString()) &&
            context.User.FindAll(ComponentClaimType)
                .Any(claim => claim.Value is "*" || claim.Value == requirement.Component) &&
            (resource.BranchId.HasValue ||
                requirement.AllowsBranchlessMetadata &&
                requirement.Component == "inventory.read" &&
                hasAssignedBranch))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
