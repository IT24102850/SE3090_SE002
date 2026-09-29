using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;
using SmeBackend.Shared;

namespace SmeBackend.Services.PlatformBilling;

/// The tenant side of Unify's own subscription: what is on sale, what a
/// change would cost, and the state machine behind subscribing, trialling,
/// cancelling and lapsing.
///
/// Money movement is not here - PlatformCheckoutService owns the gateway and
/// calls ActivateAsync once a payment has actually succeeded. Keeping the
/// two apart is what stops a client-side "I paid, honest" from ever granting
/// a plan.
public interface IPlatformSubscriptionService
{
    Task<PricingCatalogResponse> GetCatalogAsync(Guid? tenantId, string? currency, CancellationToken ct = default);
    Task<PlatformSubscriptionResponse> GetSubscriptionAsync(Guid tenantId, CancellationToken ct = default);
    Task<BillingResult<SubscriptionQuoteResponse>> QuoteAsync(Guid tenantId, SubscriptionQuoteRequest request, CancellationToken ct = default);

    /// Applies a paid term. Called by the checkout service after a payment
    /// succeeds, and directly for a change that costs nothing.
    Task<PlatformSubscriptionResponse> ActivateAsync(Guid tenantId, string planCode, string period, string currency,
        decimal amount, string? promotionCode, Guid? invoiceId, string? actorEmail, CancellationToken ct = default);

    Task<BillingResult<PlatformSubscriptionResponse>> StartTrialAsync(Guid tenantId, string planCode, string? actorEmail, CancellationToken ct = default);
    Task<BillingResult<PlatformSubscriptionResponse>> CancelAsync(Guid tenantId, CancelPlatformSubscriptionRequest request, string? actorEmail, CancellationToken ct = default);
    Task<BillingResult<PlatformSubscriptionResponse>> ResumeAsync(Guid tenantId, string? actorEmail, CancellationToken ct = default);

    Task<IReadOnlyList<PlatformInvoiceResponse>> InvoicesAsync(Guid tenantId, CancellationToken ct = default);

    /// Grants a purchased pack. Called by the checkout service on success.
    Task GrantAddOnAsync(Guid tenantId, PlatformAddOn addOn, int quantity, Guid? invoiceId, CancellationToken ct = default);

    Task<(PlatformPromotion Promotion, decimal Discount)?> ResolvePromotionAsync(
        Guid tenantId, string? code, string planCode, string period, string currency, decimal listAmount, CancellationToken ct = default);
}

public sealed class PlatformSubscriptionService : IPlatformSubscriptionService
{
    private readonly AppDbContext _db;
    private readonly IEntitlementService _entitlements;
    private readonly IPlatformGatewayProvider _gateways;
    private readonly ILogger<PlatformSubscriptionService> _logger;

    public PlatformSubscriptionService(AppDbContext db, IEntitlementService entitlements,
        IPlatformGatewayProvider gateways, ILogger<PlatformSubscriptionService> logger)
    {
        _db = db;
        _entitlements = entitlements;
        _gateways = gateways;
        _logger = logger;
    }

    // ── Catalogue ────────────────────────────────────────────────────────

    public async Task<PricingCatalogResponse> GetCatalogAsync(Guid? tenantId, string? currency, CancellationToken ct = default)
    {
        var resolved = NormalizeCurrency(currency);
        var plans = await _db.PlatformPlans.AsNoTracking()
            .Include(p => p.Prices)
            .Where(p => p.IsPublic && !p.IsRetired)
            .OrderBy(p => p.Tier)
            .ToListAsync(ct);

        var tier = 0;
        if (tenantId is { } id)
        {
            var snapshot = await _entitlements.GetAsync(id, ct);
            tier = snapshot.Tier;
        }

        var addOns = await _db.PlatformAddOns.AsNoTracking()
            .Where(a => a.IsPublic)
            .OrderBy(a => a.SortOrder)
            .ToListAsync(ct);

        PromotionResponse? featured = null;
        if (tenantId is { } promoTenant)
        {
            var offer = await BestAutoOfferAsync(promoTenant, ct);
            if (offer is not null) featured = MapPromotion(offer);
        }
        else
        {
            var offer = await _db.PlatformPromotions.AsNoTracking()
                .Where(p => p.IsActive && p.AutoApply && p.Kind == PromotionKinds.Intro)
                .ToListAsync(ct);
            var live = offer.FirstOrDefault(p => p.IsLive(DateTime.UtcNow));
            if (live is not null) featured = MapPromotion(live);
        }

        return new PricingCatalogResponse(
            resolved,
            PlatformPlanCatalog.Currencies,
            plans.Select(p => MapPlan(p, resolved)).ToList(),
            addOns.Select(a => MapAddOn(a, resolved, tier)).ToList(),
            featured);
    }

    private static PlanResponse MapPlan(PlatformPlan plan, string currency)
    {
        var limits = PlanLimits.Parse(plan.LimitsJson);
        var monthly = plan.Prices.FirstOrDefault(p => p.Currency == currency && p.Period == BillingPeriods.Monthly);

        var prices = plan.Prices
            .Where(p => p.IsActive && p.Currency == currency)
            .OrderBy(p => BillingPeriods.Months(p.Period))
            .Select(p => new PlanPriceResponse(
                p.Id,
                p.Period,
                BillingPeriods.Label(p.Period),
                p.Currency,
                p.Amount,
                p.MonthlyEquivalent,
                p.SavingsPercent,
                p.IsBestValue,
                // The anchor: the same months bought one at a time.
                monthly is null ? p.Amount : monthly.Amount * BillingPeriods.Months(p.Period)))
            .ToList();

        string[] highlights;
        try
        {
            highlights = JsonSerializer.Deserialize<string[]>(plan.HighlightsJson) ?? Array.Empty<string>();
        }
        catch (JsonException)
        {
            highlights = Array.Empty<string>();
        }

        return new PlanResponse(
            plan.Id, plan.Code, plan.Name, plan.Tier, plan.Tagline, highlights,
            plan.IsMostPopular, plan.TrialDays,
            limits.MaxBranches, limits.MaxStaffSeats, limits.MaxBookingsPerMonth,
            limits.AiRunsPerMonth, limits.SmsPerMonth, limits.SpotlightsPerMonth,
            limits.SupportResponseHours, limits.Features, prices);
    }

    private static AddOnResponse MapAddOn(PlatformAddOn addOn, string currency, int tier)
    {
        var prices = PlatformAddOnCatalog.ParsePrices(addOn.PricesJson);
        var amount = prices.TryGetValue(currency, out var a) ? a : 0m;
        var comparedAt = addOn.SavingsPercent <= 0 || addOn.SavingsPercent >= 100
            ? amount
            : Math.Round(amount / (1 - addOn.SavingsPercent / 100m), 2, MidpointRounding.AwayFromZero);

        return new AddOnResponse(
            addOn.Id, addOn.Code, addOn.Name, addOn.Tagline, addOn.Category, addOn.CreditType,
            addOn.Quantity, addOn.ExpiryDays, amount, currency, comparedAt,
            addOn.SavingsPercent, addOn.IsBestValue, addOn.MinimumTier,
            AvailableOnCurrentPlan: tier >= addOn.MinimumTier);
    }

    // ── The tenant's subscription ────────────────────────────────────────

    public async Task<PlatformSubscriptionResponse> GetSubscriptionAsync(Guid tenantId, CancellationToken ct = default)
    {
        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        var snapshot = await _entitlements.GetAsync(tenantId, ct);
        var plan = await _db.PlatformPlans.AsNoTracking().FirstOrDefaultAsync(p => p.Id == subscription.PlanId, ct);

        // The trial is offered once per business and only on a plan that has
        // one, and only from the free plan - it is an acquisition tool, not
        // a way to pause a paid subscription.
        var trialPlan = await _db.PlatformPlans.AsNoTracking()
            .Where(p => p.IsPublic && !p.IsRetired && p.TrialDays > 0)
            .OrderBy(p => p.Tier)
            .FirstOrDefaultAsync(ct);
        var trialAvailable = subscription.TrialUsedAt is null
                             && subscription.Tier == 0
                             && trialPlan is not null;

        var usage = new List<UsageMeterResponse>
        {
            await MeterAsync(tenantId, UsageMetrics.Bookings, "Bookings", snapshot.Limits.MaxBookingsPerMonth, snapshot, ct),
            await MeterAsync(tenantId, UsageMetrics.AiRuns, "AI copilot runs", snapshot.Limits.AiRunsPerMonth, snapshot, ct),
            await MeterAsync(tenantId, UsageMetrics.Sms, "SMS and WhatsApp", snapshot.Limits.SmsPerMonth, snapshot, ct),
        };

        return new PlatformSubscriptionResponse(
            tenantId,
            snapshot.PlanCode,
            snapshot.PlanName,
            snapshot.Tier,
            subscription.Status,
            snapshot.HasAccess,
            subscription.Period,
            BillingPeriods.Label(subscription.Period),
            subscription.Currency,
            subscription.Amount,
            subscription.CurrentPeriodStart,
            subscription.CurrentPeriodEnd,
            subscription.TrialEndsAt,
            trialAvailable,
            trialPlan?.TrialDays ?? 0,
            subscription.AutoRenew,
            subscription.CancelAtPeriodEnd,
            subscription.GraceEndsAt,
            snapshot.ExtraSeats,
            subscription.IsComplimentary,
            subscription.PromotionCode,
            snapshot.Limits.Features,
            usage,
            snapshot.Credits,
            subscription.LastPaymentAt);
    }

    private async Task<UsageMeterResponse> MeterAsync(Guid tenantId, string metric, string label, int? limit,
        EntitlementSnapshot snapshot, CancellationToken ct)
    {
        var used = await _entitlements.UsedThisMonthAsync(tenantId, metric, ct);
        var creditType = EntitlementService.CreditTypeFor(metric);
        return new UsageMeterResponse(metric, label, used, limit, creditType is null ? 0 : snapshot.Credit(creditType));
    }

    public async Task<IReadOnlyList<PlatformInvoiceResponse>> InvoicesAsync(Guid tenantId, CancellationToken ct = default)
    {
        var rows = await _db.PlatformInvoices.AsNoTracking()
            .Where(i => i.TenantId == tenantId)
            .OrderByDescending(i => i.IssuedAt)
            .Take(50)
            .ToListAsync(ct);
        return rows.Select(MapInvoice).ToList();
    }

    public static PlatformInvoiceResponse MapInvoice(PlatformInvoice i)
    {
        IReadOnlyList<PlatformInvoiceLine> lines;
        try
        {
            lines = JsonSerializer.Deserialize<List<PlatformInvoiceLine>>(i.LinesJson,
                        new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                    ?? new List<PlatformInvoiceLine>();
        }
        catch (JsonException)
        {
            lines = new List<PlatformInvoiceLine>();
        }

        return new PlatformInvoiceResponse(
            i.Id, i.Number, i.Kind, i.PlanCode, i.Period, i.Currency,
            i.Subtotal, i.Discount, i.Tax, i.Total, i.Status, i.PromotionCode,
            i.IssuedAt, i.DueAt, i.PaidAt, i.PeriodStart, i.PeriodEnd, lines);
    }

    // ── Quoting ──────────────────────────────────────────────────────────

    public async Task<BillingResult<SubscriptionQuoteResponse>> QuoteAsync(Guid tenantId, SubscriptionQuoteRequest request, CancellationToken ct = default)
    {
        var period = BillingPeriods.Normalize(request.Period) ?? BillingPeriods.Monthly;
        var currency = NormalizeCurrency(request.Currency);

        var plan = await _db.PlatformPlans.AsNoTracking().Include(p => p.Prices)
            .FirstOrDefaultAsync(p => p.Code == request.PlanCode && !p.IsRetired, ct);
        if (plan is null) return BillingResult<SubscriptionQuoteResponse>.NotFound("That plan does not exist.");

        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        var now = DateTime.UtcNow;

        if (plan.Tier == 0)
        {
            // Downgrading to free is never a purchase; it is a cancellation.
            return BillingResult<SubscriptionQuoteResponse>.BadRequest(
                "Starter is free. Cancel your current plan to move back to it.");
        }

        if (plan.Code == subscription.PlanCode && period == subscription.Period
            && subscription.Status is PlatformSubscriptionStatuses.Active or PlatformSubscriptionStatuses.Trialing
            && !subscription.CancelAtPeriodEnd)
            return BillingResult<SubscriptionQuoteResponse>.BadRequest("You are already on this plan and term.");

        var price = plan.Prices.FirstOrDefault(p => p.IsActive && p.Currency == currency && p.Period == period);
        if (price is null)
            return BillingResult<SubscriptionQuoteResponse>.BadRequest($"{plan.Name} is not sold in {currency} on a {BillingPeriods.Label(period).ToLowerInvariant()} term.");

        var lines = new List<PlatformInvoiceLine>
        {
            new($"{plan.Name} - {BillingPeriods.Label(period)}", 1, price.Amount, price.Amount),
        };

        // Unused time on a paid plan is credited, so an upgrade mid-term is
        // never a second payment for days already bought.
        var proration = Proration(subscription, now);
        if (proration > 0)
            lines.Add(new PlatformInvoiceLine("Credit for unused time on your current plan", 1, -proration, -proration));

        var promo = await ResolvePromotionAsync(tenantId, request.PromotionCode, plan.Code, period, currency, price.Amount, ct);
        var discount = promo?.Discount ?? 0m;
        if (discount > 0)
            lines.Add(new PlatformInvoiceLine($"Offer {promo!.Value.Promotion.Code}", 1, -discount, -discount));

        var total = Math.Max(0m, BillingRules.Round(price.Amount - proration - discount));

        return BillingResult<SubscriptionQuoteResponse>.Ok(new SubscriptionQuoteResponse(
            plan.Code, plan.Name, period, BillingPeriods.Label(period), currency,
            price.Amount, discount, proration, total,
            RenewalAmount: price.Amount,
            promo?.Promotion.Code,
            promo is null ? null : PromotionMessage(promo.Value.Promotion, price.Amount),
            now, now.AddMonths(BillingPeriods.Months(period)), lines));
    }

    /// The unused share of what the tenant already paid for, in the currency
    /// of their current term. Only ever a credit, never a charge: a
    /// downgrade does not bill them for the difference.
    public static decimal Proration(PlatformSubscription subscription, DateTime now)
    {
        if (subscription.Amount <= 0 || subscription.CurrentPeriodEnd is not { } end) return 0m;
        if (subscription.Status is not (PlatformSubscriptionStatuses.Active or PlatformSubscriptionStatuses.Cancelling)) return 0m;
        if (end <= now) return 0m;

        var total = (end - subscription.CurrentPeriodStart).TotalDays;
        if (total <= 0) return 0m;
        var remaining = (end - now).TotalDays;
        return BillingRules.Round(subscription.Amount * (decimal)(remaining / total));
    }

    // ── Promotions ───────────────────────────────────────────────────────

    public async Task<(PlatformPromotion Promotion, decimal Discount)?> ResolvePromotionAsync(
        Guid tenantId, string? code, string planCode, string period, string currency, decimal listAmount, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        PlatformPromotion? promotion;

        if (string.IsNullOrWhiteSpace(code))
        {
            promotion = await BestAutoOfferAsync(tenantId, ct);
        }
        else
        {
            var typed = code.Trim();
            promotion = await _db.PlatformPromotions
                .FirstOrDefaultAsync(p => p.Code.ToUpper() == typed.ToUpper(), ct);
            if (promotion is null || !promotion.IsLive(now)) return null;
            if (!await QualifiesAsync(tenantId, promotion, ct)) return null;
        }

        if (promotion is null) return null;
        if (promotion.PlanCode is { } onlyPlan && !string.Equals(onlyPlan, planCode, StringComparison.OrdinalIgnoreCase)) return null;
        if (promotion.Period is { } onlyPeriod && !string.Equals(onlyPeriod, period, StringComparison.OrdinalIgnoreCase)) return null;

        var discount = promotion.PercentOff is { } percent
            ? BillingRules.Round(listAmount * percent / 100m)
            : promotion.AmountCurrency is null || string.Equals(promotion.AmountCurrency, currency, StringComparison.OrdinalIgnoreCase)
                ? promotion.AmountOff ?? 0m
                : 0m; // a fixed amount in another currency is not convertible here

        discount = Math.Min(discount, listAmount);
        return discount <= 0 ? null : (promotion, discount);
    }

    /// The best offer a tenant can take without typing anything. Win-back
    /// beats intro beats loyalty, and within a kind the biggest discount
    /// wins - the tenant should never find a better code than the one the
    /// screen already showed them.
    private async Task<PlatformPromotion?> BestAutoOfferAsync(Guid tenantId, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var candidates = await _db.PlatformPromotions.AsNoTracking()
            .Where(p => p.IsActive && p.AutoApply)
            .ToListAsync(ct);

        var live = candidates.Where(p => p.IsLive(now)).ToList();
        if (live.Count == 0) return null;

        var qualified = new List<PlatformPromotion>();
        foreach (var promotion in live)
            if (await QualifiesAsync(tenantId, promotion, ct))
                qualified.Add(promotion);

        return qualified
            .OrderBy(p => p.Kind switch
            {
                PromotionKinds.WinBack => 0,
                PromotionKinds.Intro => 1,
                PromotionKinds.Loyalty => 2,
                _ => 3,
            })
            .ThenByDescending(p => p.PercentOff ?? 0)
            .FirstOrDefault();
    }

    private async Task<bool> QualifiesAsync(Guid tenantId, PlatformPromotion promotion, CancellationToken ct)
    {
        if (await _db.PlatformPromotionRedemptions.AnyAsync(r => r.TenantId == tenantId && r.PromotionId == promotion.Id, ct))
            return false;

        if (!promotion.NewTenantsOnly && !promotion.LapsedTenantsOnly) return true;

        var everPaid = await _db.PlatformSubscriptionEvents
            .AnyAsync(e => e.TenantId == tenantId && (e.EventType == "subscribe" || e.EventType == "upgrade" || e.EventType == "renew"), ct);
        if (promotion.NewTenantsOnly && everPaid) return false;

        if (promotion.LapsedTenantsOnly)
        {
            var subscription = await _db.PlatformSubscriptions.AsNoTracking().FirstOrDefaultAsync(s => s.TenantId == tenantId, ct);
            var lapsed = everPaid && (subscription is null || subscription.Tier == 0
                                      || subscription.Status == PlatformSubscriptionStatuses.Expired);
            if (!lapsed) return false;
        }

        return true;
    }

    public static PromotionResponse MapPromotion(PlatformPromotion p) => new(
        p.Code, p.Name, p.Kind, p.PercentOff, p.AmountOff, p.AmountCurrency,
        p.PlanCode, p.Period, p.Terms, p.EndsAt,
        p.PercentOff is { } percent
            ? $"{percent}% off your first {(p.Terms > 1 ? $"{p.Terms} terms" : "term")}"
            : $"{p.AmountCurrency} {p.AmountOff:N2} off your first term");

    private static string PromotionMessage(PlatformPromotion p, decimal listAmount) =>
        p.Terms > 1
            ? $"{p.Name} applies to your first {p.Terms} terms. After that it renews at the standard price."
            : $"{p.Name} applies to this term only. It renews at the standard price.";

    // ── State machine ────────────────────────────────────────────────────

    public async Task<PlatformSubscriptionResponse> ActivateAsync(Guid tenantId, string planCode, string period, string currency,
        decimal amount, string? promotionCode, Guid? invoiceId, string? actorEmail, CancellationToken ct = default)
    {
        var plan = await _db.PlatformPlans.Include(p => p.Prices).FirstAsync(p => p.Code == planCode, ct);
        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        var now = DateTime.UtcNow;
        var from = subscription.PlanCode;
        // Read off the row before it is rewritten - the tier the tenant is
        // actually on, rather than one inferred from a plan code.
        var fromTier = subscription.Tier;
        var wasTrialing = subscription.Status == PlatformSubscriptionStatuses.Trialing;

        var price = plan.Prices.FirstOrDefault(p => p.IsActive && p.Currency == currency && p.Period == period);

        subscription.PlanId = plan.Id;
        subscription.PlanCode = plan.Code;
        subscription.Tier = plan.Tier;
        subscription.PriceId = price?.Id;
        subscription.Status = PlatformSubscriptionStatuses.Active;
        subscription.Period = period;
        subscription.Currency = currency;
        // The renewal is at the list price, not at whatever a first-term
        // offer brought this charge down to. The quote said so in words.
        subscription.Amount = price?.Amount ?? amount;
        subscription.CurrentPeriodStart = now;
        subscription.CurrentPeriodEnd = now.AddMonths(BillingPeriods.Months(period));
        subscription.TrialEndsAt = null;
        subscription.AutoRenew = true;
        subscription.CancelAtPeriodEnd = false;
        subscription.CancelRequestedAt = null;
        subscription.CancelReason = null;
        subscription.GraceEndsAt = null;
        subscription.FailedRenewalAttempts = 0;
        subscription.PromotionCode = promotionCode;
        subscription.DiscountAmount = price is null ? 0m : Math.Max(0m, price.Amount - amount);
        subscription.LastPaymentAt = amount > 0 ? now : subscription.LastPaymentAt;
        subscription.StartedAt ??= now;
        subscription.UpdatedAt = now;

        // The event names are what the owner console's funnel is counted
        // from, so they have to be exactly right: a downgrade recorded as an
        // upgrade would flatter the revenue chart.
        var eventType = wasTrialing ? "trial.convert"
            : from == plan.Code ? "renew"
            : fromTier == 0 ? "subscribe"
            : plan.Tier > fromTier ? "upgrade"
            : plan.Tier < fromTier ? "downgrade"
            : "subscribe";

        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscription.Id,
            EventType = eventType,
            FromPlanCode = from,
            ToPlanCode = plan.Code,
            Period = period,
            Currency = currency,
            Amount = amount,
            ActorEmail = actorEmail,
            Detail = invoiceId is null ? null : $"invoice:{invoiceId}",
        });

        await _db.SaveChangesAsync(ct);
        await GrantTermCreditsAsync(tenantId, plan, invoiceId, ct);
        _entitlements.Invalidate(tenantId);

        NotificationHelper.Queue(_db, tenantId, null, "SubscriptionActivated", $"{plan.Name} is active",
            $"Your Unify subscription is now {plan.Name} ({BillingPeriods.Label(period)}). It renews on {subscription.CurrentPeriodEnd:d MMM yyyy}.");
        await _db.SaveChangesAsync(ct);

        return await GetSubscriptionAsync(tenantId, ct);
    }

    /// The Spotlights a paid plan includes. Handed out at the start of every
    /// term and expiring with it, so they are a reason to come back this
    /// month rather than a balance that piles up unused.
    private async Task GrantTermCreditsAsync(Guid tenantId, PlatformPlan plan, Guid? invoiceId, CancellationToken ct)
    {
        var limits = PlanLimits.Parse(plan.LimitsJson);
        if (limits.SpotlightsPerMonth <= 0) return;

        _db.PlatformCreditEntries.Add(new PlatformCreditEntry
        {
            TenantId = tenantId,
            CreditType = PlatformCreditTypes.Spotlight,
            Delta = limits.SpotlightsPerMonth,
            Remaining = limits.SpotlightsPerMonth,
            Reason = "plan-grant",
            InvoiceId = invoiceId,
            Detail = plan.Code,
            ExpiresAt = DateTime.UtcNow.AddDays(31),
        });
        await _db.SaveChangesAsync(ct);
        _entitlements.Invalidate(tenantId);
    }

    public async Task<BillingResult<PlatformSubscriptionResponse>> StartTrialAsync(Guid tenantId, string planCode, string? actorEmail, CancellationToken ct = default)
    {
        var plan = await _db.PlatformPlans.FirstOrDefaultAsync(p => p.Code == planCode && !p.IsRetired, ct);
        if (plan is null) return BillingResult<PlatformSubscriptionResponse>.NotFound("That plan does not exist.");
        if (plan.TrialDays <= 0) return BillingResult<PlatformSubscriptionResponse>.BadRequest($"{plan.Name} does not have a free trial.");

        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        if (subscription.TrialUsedAt is not null)
            return BillingResult<PlatformSubscriptionResponse>.Conflict("This business has already used its free trial.");
        if (subscription.Tier > 0)
            return BillingResult<PlatformSubscriptionResponse>.Conflict("You are already on a paid plan.");

        var now = DateTime.UtcNow;
        subscription.PlanId = plan.Id;
        subscription.PlanCode = plan.Code;
        subscription.Tier = plan.Tier;
        subscription.PriceId = null;
        subscription.Status = PlatformSubscriptionStatuses.Trialing;
        subscription.Period = BillingPeriods.Monthly;
        subscription.Amount = 0m;
        subscription.CurrentPeriodStart = now;
        subscription.CurrentPeriodEnd = now.AddDays(plan.TrialDays);
        subscription.TrialEndsAt = now.AddDays(plan.TrialDays);
        subscription.TrialUsedAt = now;
        // No card was taken, so nothing can renew. The trial ends by
        // dropping to Starter, and the tenant chooses to pay or not.
        subscription.AutoRenew = false;
        subscription.CancelAtPeriodEnd = false;
        subscription.UpdatedAt = now;

        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscription.Id,
            EventType = "trial.start",
            ToPlanCode = plan.Code,
            ActorEmail = actorEmail,
            Detail = $"{plan.TrialDays} days",
        });

        NotificationHelper.Queue(_db, tenantId, null, "TrialStarted", $"Your {plan.Name} trial has started",
            $"You have {plan.TrialDays} days of {plan.Name} with everything switched on. It ends on {subscription.TrialEndsAt:d MMM yyyy}.");

        await _db.SaveChangesAsync(ct);
        await GrantTermCreditsAsync(tenantId, plan, null, ct);
        _entitlements.Invalidate(tenantId);

        return BillingResult<PlatformSubscriptionResponse>.Ok(await GetSubscriptionAsync(tenantId, ct));
    }

    public async Task<BillingResult<PlatformSubscriptionResponse>> CancelAsync(Guid tenantId, CancelPlatformSubscriptionRequest request, string? actorEmail, CancellationToken ct = default)
    {
        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        if (subscription.Tier == 0)
            return BillingResult<PlatformSubscriptionResponse>.BadRequest("You are on the free plan; there is nothing to cancel.");
        if (subscription.CancelAtPeriodEnd)
            return BillingResult<PlatformSubscriptionResponse>.BadRequest("This subscription is already set to end at the close of the term.");

        var now = DateTime.UtcNow;
        var trialing = subscription.Status == PlatformSubscriptionStatuses.Trialing;

        subscription.CancelRequestedAt = now;
        subscription.CancelReason = request.Reason;
        subscription.AutoRenew = false;

        // Immediate cancellation is only offered inside a trial, where no
        // money changed hands. A paid term is never cut short - the tenant
        // keeps every day they bought, which is also the cheapest way to
        // keep the door open for them to come back.
        if (trialing && request.Immediate)
        {
            await DropToStarterAsync(subscription, "cancel", actorEmail, ct);
        }
        else
        {
            subscription.CancelAtPeriodEnd = true;
            subscription.Status = PlatformSubscriptionStatuses.Cancelling;
            subscription.UpdatedAt = now;
            _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
            {
                TenantId = tenantId,
                SubscriptionId = subscription.Id,
                EventType = "cancel",
                FromPlanCode = subscription.PlanCode,
                ActorEmail = actorEmail,
                Detail = request.Reason,
            });
            NotificationHelper.Queue(_db, tenantId, null, "SubscriptionCancelled", "Your plan will end at the end of the term",
                $"You keep everything in {subscription.PlanCode} until {subscription.CurrentPeriodEnd:d MMM yyyy}, then move to Starter. You can undo this at any time before then.");
            await _db.SaveChangesAsync(ct);
        }

        _entitlements.Invalidate(tenantId);
        return BillingResult<PlatformSubscriptionResponse>.Ok(await GetSubscriptionAsync(tenantId, ct));
    }

    public async Task<BillingResult<PlatformSubscriptionResponse>> ResumeAsync(Guid tenantId, string? actorEmail, CancellationToken ct = default)
    {
        var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
        if (!subscription.CancelAtPeriodEnd)
            return BillingResult<PlatformSubscriptionResponse>.BadRequest("This subscription is not scheduled to end.");

        subscription.CancelAtPeriodEnd = false;
        subscription.CancelRequestedAt = null;
        subscription.CancelReason = null;
        subscription.AutoRenew = true;
        subscription.Status = PlatformSubscriptionStatuses.Active;
        subscription.UpdatedAt = DateTime.UtcNow;

        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscription.Id,
            EventType = "resume",
            ToPlanCode = subscription.PlanCode,
            ActorEmail = actorEmail,
        });
        await _db.SaveChangesAsync(ct);
        _entitlements.Invalidate(tenantId);

        return BillingResult<PlatformSubscriptionResponse>.Ok(await GetSubscriptionAsync(tenantId, ct));
    }

    /// Moves a subscription back to the free plan. The one path out of every
    /// ending - cancellation, an expired trial, a renewal nobody paid.
    public async Task DropToStarterAsync(PlatformSubscription subscription, string eventType, string? actorEmail, CancellationToken ct)
    {
        var starter = await _db.PlatformPlans.FirstAsync(p => p.Code == PlatformPlanCodes.Starter, ct);
        var from = subscription.PlanCode;
        var now = DateTime.UtcNow;

        subscription.PlanId = starter.Id;
        subscription.PlanCode = starter.Code;
        subscription.Tier = starter.Tier;
        subscription.PriceId = null;
        subscription.Status = PlatformSubscriptionStatuses.Expired;
        subscription.Amount = 0m;
        subscription.Period = BillingPeriods.Monthly;
        subscription.CurrentPeriodStart = now;
        subscription.CurrentPeriodEnd = null;
        subscription.TrialEndsAt = null;
        subscription.AutoRenew = false;
        subscription.CancelAtPeriodEnd = false;
        subscription.GraceEndsAt = null;
        subscription.ExtraSeats = 0;
        subscription.PromotionCode = null;
        subscription.DiscountAmount = 0m;
        subscription.UpdatedAt = now;

        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = subscription.TenantId,
            SubscriptionId = subscription.Id,
            EventType = eventType,
            FromPlanCode = from,
            ToPlanCode = starter.Code,
            ActorEmail = actorEmail,
        });

        NotificationHelper.Queue(_db, subscription.TenantId, null, "SubscriptionEnded", "You are back on Starter",
            "Your paid plan has ended. Your data is all still here - resubscribe whenever you are ready and everything switches back on.");

        await _db.SaveChangesAsync(ct);
        _entitlements.Invalidate(subscription.TenantId);
        _logger.LogInformation("Tenant {TenantId} moved from {From} to Starter ({Event}).", subscription.TenantId, from, eventType);
    }

    // ── Add-ons ──────────────────────────────────────────────────────────

    public async Task GrantAddOnAsync(Guid tenantId, PlatformAddOn addOn, int quantity, Guid? invoiceId, CancellationToken ct = default)
    {
        if (quantity <= 0) quantity = 1;

        if (addOn.CreditType == PlatformCreditTypes.Seat)
        {
            var subscription = await _entitlements.EnsureSubscriptionAsync(tenantId, ct);
            subscription.ExtraSeats += addOn.Quantity * quantity;
            subscription.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            _db.PlatformCreditEntries.Add(new PlatformCreditEntry
            {
                TenantId = tenantId,
                CreditType = addOn.CreditType,
                Delta = addOn.Quantity * quantity,
                Remaining = addOn.Quantity * quantity,
                Reason = "purchase",
                InvoiceId = invoiceId,
                Detail = addOn.Code,
                ExpiresAt = addOn.ExpiryDays > 0 ? DateTime.UtcNow.AddDays(addOn.ExpiryDays) : null,
            });
        }

        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            EventType = "addon.purchase",
            Detail = $"{addOn.Code} x{quantity}",
        });

        await _db.SaveChangesAsync(ct);
        _entitlements.Invalidate(tenantId);
    }

    // ── helpers ──────────────────────────────────────────────────────────

    public string NormalizeCurrency(string? currency)
    {
        if (string.IsNullOrWhiteSpace(currency)) return _gateways.DefaultCurrency;
        var upper = currency.Trim().ToUpperInvariant();
        return PlatformPlanCatalog.Currencies.Contains(upper) ? upper : _gateways.DefaultCurrency;
    }
}
