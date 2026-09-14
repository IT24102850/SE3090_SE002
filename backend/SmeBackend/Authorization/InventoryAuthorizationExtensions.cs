using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SmeBackend.Authorization;

public static class InventoryAuthorizationExtensions
{
    public static async Task<bool> IsInventoryOperationAuthorizedAsync(
        this ControllerBase controller,
        IAuthorizationService authorizationService,
        string policy,
        Guid tenantId,
        Guid? branchId)
    {
        var result = await authorizationService.AuthorizeAsync(
            controller.User,
            new InventoryAccessResource(tenantId, branchId),
            policy);

        return result.Succeeded;
    }
}
