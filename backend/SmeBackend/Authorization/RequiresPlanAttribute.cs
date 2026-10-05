using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using SmeBackend.Services.PlatformBilling;
using SmeBackend.Shared;

namespace SmeBackend.Authorization;

/// Gates an endpoint on the tenant's Unify subscription.
///
/// This is not authorisation and deliberately does not look like it. A 403
/// says "not you"; this says "not on this plan", which is a different
/// problem with a different fix, so it answers 402 Payment Required with the
/// PaywallInfo that tells the app exactly what to offer. The apps have one
/// interceptor for 402 and one paywall sheet, and every gate in the product
/// reaches it through here.
///
/// The paywall fires at the moment of need rather than at sign-in: the
/// tenant is refused the thing they were just trying to do, with the plan
/// that unblocks it named. That placement is most of why it converts.
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RequiresPlanFeatureAttribute : Attribute, IAsyncActionFilter
{
    private readonly string _feature;

    public RequiresPlanFeatureAttribute(string feature) => _feature = feature;

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        // Customers consume tenant-provided features; subscription ownership
        // and payment belong to the tenant admin. In particular, customer AI
        // planning must not open a customer paywall.
        if (context.HttpContext.User.IsInRole(Roles.Customer))
        {
            await next();
            return;
        }

        var tenantId = PlanGate.TenantId(context.HttpContext.User);
        if (tenantId is null)
        {
            // No tenant in the token: authentication has already had its say
            // and this filter has nothing to add.
            await next();
            return;
        }

        var entitlements = context.HttpContext.RequestServices.GetRequiredService<IEntitlementService>();
        var paywall = await entitlements.CheckFeatureAsync(tenantId.Value, _feature, context.HttpContext.RequestAborted);
        if (paywall is not null)
        {
            context.Result = PlanGate.PaymentRequired(paywall);
            return;
        }

        await next();
    }
}

/// Counts an action against a monthly allowance, and falls back to bought
/// credits when the allowance is spent.
///
/// The count happens *after* the action, and only when it produced a success:
/// a copilot call that failed on a timeout has not used anybody's AI run, and
/// billing for it is the kind of small dishonesty that costs more in support
/// than it earns.
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class MetersPlanQuotaAttribute : Attribute, IAsyncActionFilter
{
    private readonly string _metric;
    private readonly int _amount;

    public MetersPlanQuotaAttribute(string metric, int amount = 1)
    {
        _metric = metric;
        _amount = amount;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        // AI usage from a customer is covered by the business subscription.
        // Only tenant-side operators consume the tenant's paid quota.
        if (context.HttpContext.User.IsInRole(Roles.Customer))
        {
            await next();
            return;
        }

        var tenantId = PlanGate.TenantId(context.HttpContext.User);
        if (tenantId is null)
        {
            await next();
            return;
        }

        var entitlements = context.HttpContext.RequestServices.GetRequiredService<Services.PlatformBilling.IEntitlementService>();
        var ct = context.HttpContext.RequestAborted;

        var decision = await entitlements.CheckQuotaAsync(tenantId.Value, _metric, _amount, ct);
        if (!decision.Allowed)
        {
            context.Result = PlanGate.PaymentRequired(decision.Paywall!);
            return;
        }

        var executed = await next();
        if (executed.Exception is not null && !executed.ExceptionHandled) return;

        var status = executed.Result switch
        {
            IStatusCodeActionResult coded => coded.StatusCode ?? StatusCodes.Status200OK,
            null => context.HttpContext.Response.StatusCode,
            _ => StatusCodes.Status200OK,
        };
        if (status is >= 200 and < 300)
            await entitlements.ConsumeAsync(tenantId.Value, _metric, decision, _amount, ct);
    }
}

public static class PlanGate
{
    /// The status code the whole feature hangs off. 402 is unused elsewhere
    /// in this API, so an interceptor can key on it with no ambiguity.
    public const int PaymentRequiredStatus = 402;

    public static Guid? TenantId(ClaimsPrincipal user) =>
        Guid.TryParse(user.FindFirst("tenantId")?.Value, out var id) ? id : null;

    public static ObjectResult PaymentRequired(PaywallInfo paywall) =>
        new(new
        {
            status = "upgradeRequired",
            message = paywall.Message,
            paywall = new
            {
                reason = paywall.Reason,
                feature = paywall.Feature,
                metric = paywall.Metric,
                used = paywall.Used,
                limit = paywall.Limit,
                currentPlan = paywall.CurrentPlanCode,
                requiredPlan = paywall.RequiredPlanCode,
                requiredPlanName = paywall.RequiredPlanName,
                addOnCode = paywall.AddOnCode,
                upgradeUrl = "/subscription",
            },
        })
        { StatusCode = PaymentRequiredStatus };
}
