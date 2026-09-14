# Inventory endpoint authorization plan

JWT bearer authentication is registered in `Program.cs`. Configure a local signing
key without committing it:

```powershell
dotnet user-secrets set "Jwt:Key" "a-long-random-development-secret-at-least-32-characters" --project backend/SmeBackend
```

The auth/login implementation must issue tokens with these claims:

- `ClaimTypes.NameIdentifier`: the user ID.
- `ClaimTypes.Role`: the numeric or string role accepted by the configured role
  mapper; issue role names (`Admin`, `Manager`, or `Staff`) to match endpoint
  authorization. The API explicitly validates this claim type, so do not issue a
  custom claim named `role` unless the token issuer maps it to `ClaimTypes.Role`.
- `tenant_id`: the authenticated user's tenant ID. Inventory queries and writes
  must scope data to this claim; role authorization alone does not provide tenant
  isolation.
- `branch_id`: required for Managers and set to their assigned branch ID.
- `component`: zero or more Staff grants, such as `inventory.read`,
  `inventory.write`, `purchase-orders.read`, or `purchase-orders.write`.

Use `[Authorize]` to require a valid token, then run resource-based authorization
after loading the requested inventory/PO's tenant and branch. This prevents a
caller from choosing a tenant or branch in the request body. Available policies
are `InventoryRead`, `InventoryWrite`, `PurchaseOrderRead`, and
`PurchaseOrderWrite`.

```csharp
[Authorize]
[HttpPut("{id:guid}")]
public async Task<IActionResult> Update(Guid id, UpdateInventoryItemRequest request,
    [FromServices] IAuthorizationService authorizationService)
{
    var stock = await _db.InventoryStocks.FindAsync(id);
    if (stock is null) return NotFound();

    if (!await this.IsInventoryOperationAuthorizedAsync(
            authorizationService, InventoryAuthorizationPolicies.InventoryWrite,
            stock.TenantId, stock.BranchId))
        return Forbid();

    // update the already-authorized stock record
}
```

The policies enforce this scope:

- `Admin`: all inventory and PO components within the `tenant_id` claim.
- `Manager`: any component, but only where resource `BranchId` equals their
  `branch_id` claim. Tenant-wide items must be actioned by an Admin or explicitly
  modeled as a branch operation.
- `Staff`: only components granted as repeated `component` claims, such as
  `inventory.read` or `purchase-orders.write`, within their tenant.

Do not apply the following broad role attribute by itself: it grants Managers
cross-branch access and Staff all inventory components. Resource-based checks
are required for every inventory and PO action.

// Insufficient on its own for inventory/PO operations:

```csharp
using Microsoft.AspNetCore.Authorization;

[Authorize(Roles = "Admin,Manager,Staff")]
[ApiController]
[Route("api/inventory-items")]
public class InventoryItemsController : ControllerBase
{
}
```

Use the same restriction for supplier and stock-management write endpoints. When
customer-facing read endpoints are added, leave them anonymous only if their data
is deliberately public; otherwise use `[Authorize]` with tenant scoping.
