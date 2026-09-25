using System.Security.Claims;
using SmeBackend.Shared;

namespace SmeBackend.Services.Billing;

/// Who is calling: every billing operation is scoped by it. A Customer only
/// ever sees and pays their own invoices, subscriptions and claims.
public sealed record BillingActor(Guid TenantId, Guid? UserId, string Role)
{
    public bool IsCustomer => Role == Roles.Customer;
    public bool IsAdmin => Role == Roles.Admin;
    public bool IsStaff => Role is Roles.Admin or Roles.Manager or Roles.Staff;

    public static BillingActor? FromPrincipal(ClaimsPrincipal user)
    {
        if (!Guid.TryParse(user.FindFirst("tenantId")?.Value, out var tenantId)) return null;
        Guid? userId = Guid.TryParse(user.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var uid) ? uid : null;
        var role = user.FindFirst(ClaimTypes.Role)?.Value ?? Roles.Customer;
        return new BillingActor(tenantId, userId, role);
    }
}

public sealed record BillingResult<T>(bool Success, int StatusCode, string? Error, T? Value)
{
    public static BillingResult<T> Ok(T value) => new(true, 200, null, value);
    public static BillingResult<T> Created(T value) => new(true, 201, null, value);
    /// Accepted for approval: nothing applied yet, a request was opened.
    public static BillingResult<T> Accepted(T value) => new(true, 202, null, value);
    public static BillingResult<T> BadRequest(string error) => new(false, 400, error, default);
    public static BillingResult<T> Forbidden(string error) => new(false, 403, error, default);
    public static BillingResult<T> NotFound(string error) => new(false, 404, error, default);
    public static BillingResult<T> Conflict(string error) => new(false, 409, error, default);
    public static BillingResult<T> Unavailable(string error) => new(false, 503, error, default);
    public static BillingResult<T> BadGateway(string error) => new(false, 502, error, default);
}
