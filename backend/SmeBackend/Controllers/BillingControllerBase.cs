using Microsoft.AspNetCore.Mvc;
using SmeBackend.Services.Billing;

namespace SmeBackend.Controllers;

/// Shared plumbing for the billing controllers: resolving the caller and
/// turning a BillingResult into the right HTTP response.
public abstract class BillingControllerBase : ControllerBase
{
    protected BillingActor? Actor => BillingActor.FromPrincipal(User);

    protected ActionResult MissingTenant() =>
        Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });

    /// The spec's endpoints take ?tenantId=; the token is what decides the
    /// tenant, so a query value that disagrees with it is refused rather than
    /// silently ignored.
    protected ActionResult? RejectForeignTenant(BillingActor actor, Guid? requestedTenantId) =>
        requestedTenantId is { } t && t != Guid.Empty && t != actor.TenantId
            ? StatusCode(StatusCodes.Status403Forbidden, new { message = "You can only access your own business's billing data." })
            : null;

    protected ActionResult FromResult<T>(BillingResult<T> result) =>
        result.Success
            ? result.StatusCode switch
            {
                201 => StatusCode(StatusCodes.Status201Created, result.Value),
                202 => StatusCode(StatusCodes.Status202Accepted, result.Value),
                _ => Ok(result.Value),
            }
            : StatusCode(result.StatusCode, new { message = result.Error });

    protected ActionResult FromResult<T, TOut>(BillingResult<T> result, Func<T, TOut> project) =>
        result.Success
            ? StatusCode(result.StatusCode, project(result.Value!))
            : StatusCode(result.StatusCode, new { message = result.Error });

    protected string PublicBaseUrl() => $"{Request.Scheme}://{Request.Host}";
}
