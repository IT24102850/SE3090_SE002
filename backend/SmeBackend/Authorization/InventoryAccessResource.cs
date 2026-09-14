namespace SmeBackend.Authorization;

/// <summary>
/// The scope of an inventory or purchase-order operation being authorized.
/// </summary>
public sealed record InventoryAccessResource(Guid TenantId, Guid? BranchId);
