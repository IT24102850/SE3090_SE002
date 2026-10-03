using Microsoft.AspNetCore.Authorization;

namespace SmeBackend.Authorization;

public sealed class InventoryAccessRequirement(
    string component,
    bool allowsBranchlessMetadata = false) : IAuthorizationRequirement
{
    public string Component { get; } = component;
    public bool AllowsBranchlessMetadata { get; } = allowsBranchlessMetadata;
}
