using Microsoft.AspNetCore.Authorization;

namespace SmeBackend.Authorization;

public sealed class InventoryAccessRequirement(string component) : IAuthorizationRequirement
{
    public string Component { get; } = component;
}
