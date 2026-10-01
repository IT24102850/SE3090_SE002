namespace SmeBackend.Services;

/// <summary>
/// Who the current request belongs to, for the booking history timeline.
///
/// Set once per request by TenantResolutionMiddleware from the JWT, exactly
/// as the tenant is. A background service (the hold sweeper, the reminder
/// dispatcher) leaves it unset, and its changes are recorded as "System" -
/// which is the honest answer, not a missing one.
/// </summary>
public interface ICurrentActor
{
    Guid? UserId { get; }
    string? Role { get; }
    void Set(Guid? userId, string? role);
}

public sealed class CurrentActor : ICurrentActor
{
    public Guid? UserId { get; private set; }
    public string? Role { get; private set; }

    public void Set(Guid? userId, string? role)
    {
        UserId = userId;
        Role = role;
    }
}
