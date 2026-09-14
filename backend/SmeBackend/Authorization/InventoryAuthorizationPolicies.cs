using Microsoft.AspNetCore.Authorization;

namespace SmeBackend.Authorization;

public static class InventoryAuthorizationPolicies
{
    public const string InventoryRead = "InventoryRead";
    public const string InventoryWrite = "InventoryWrite";
    public const string PurchaseOrderRead = "PurchaseOrderRead";
    public const string PurchaseOrderWrite = "PurchaseOrderWrite";

    public static void AddInventoryPolicies(AuthorizationOptions options)
    {
        Add(options, InventoryRead, "inventory.read");
        Add(options, InventoryWrite, "inventory.write");
        Add(options, PurchaseOrderRead, "purchase-orders.read");
        Add(options, PurchaseOrderWrite, "purchase-orders.write");
    }

    private static void Add(AuthorizationOptions options, string policyName, string component)
    {
        options.AddPolicy(policyName, policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.AddRequirements(new InventoryAccessRequirement(component));
        });
    }
}
