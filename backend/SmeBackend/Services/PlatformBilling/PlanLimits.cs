using System.Text.Json;
using System.Text.Json.Serialization;

namespace SmeBackend.Services.PlatformBilling;

/// What a plan actually grants. Stored as the plan's LimitsJson so a pricing
/// change is one catalogue edit rather than a migration.
///
/// A null cap means unlimited; a zero cap means none at all. That
/// distinction is load-bearing - Starter gets 0 AI runs, Prime gets null -
/// so every read goes through the helpers below rather than comparing ints.
public sealed record PlanLimits
{
    public int? MaxBranches { get; init; }
    public int? MaxStaffSeats { get; init; }
    public int? MaxResources { get; init; }
    public int? MaxBookingsPerMonth { get; init; }
    public int? AiRunsPerMonth { get; init; }
    public int? SmsPerMonth { get; init; }

    /// Spotlight credits handed out at the start of each term - Tinder gives
    /// its Plus and Gold subscribers a free Boost a month for the same
    /// reason: it teaches the habit the pack is sold on.
    public int SpotlightsPerMonth { get; init; }

    /// Feature codes this plan unlocks - see PlanFeatures.
    public string[] Features { get; init; } = Array.Empty<string>();

    /// Hours to first response on a support request. Null = best effort.
    public int? SupportResponseHours { get; init; }

    public bool Has(string feature) =>
        Features.Contains(feature, StringComparer.OrdinalIgnoreCase);

    /// True when `used` is already at or past the cap. Unlimited never is.
    public static bool Exceeds(int? cap, int used) => cap is { } c && used >= c;

    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static PlanLimits Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new PlanLimits();
        try
        {
            return JsonSerializer.Deserialize<PlanLimits>(json, Json) ?? new PlanLimits();
        }
        catch (JsonException)
        {
            // A limits blob we cannot read must not accidentally hand out
            // everything: fall back to the most restrictive shape there is.
            return new PlanLimits { MaxBranches = 1, MaxStaffSeats = 1 };
        }
    }

    public string ToJson() => JsonSerializer.Serialize(this, Json);
}

/// Every gate in the product, named once. A feature code is what an endpoint
/// asks for and what a plan lists, so adding a gate is one constant plus one
/// attribute.
public static class PlanFeatures
{
    /// More than the one branch every business starts with.
    public const string MultiBranch = "multi-branch";
    /// The agentic AI surfaces - Schedule Copilot, the billing copilot,
    /// StockSense, the customer planner.
    public const string AiAgents = "ai-agents";
    /// Take card payments from their own customers (their PaymentGateway rows).
    public const string PaymentGateways = "payment-gateways";
    /// The full inventory module: purchase orders, suppliers, stock analytics.
    public const string InventoryPro = "inventory-pro";
    /// Analytics beyond the standard dashboard - cohort, forecast, exports.
    public const string AdvancedAnalytics = "advanced-analytics";
    /// Be listed in the public directory and take bookings from it.
    public const string PublicDirectory = "public-directory";
    /// The embeddable booking widget for their own website.
    public const string EmbedWidget = "embed-widget";
    /// Custom dynamic forms and the invoice designer.
    public const string CustomBranding = "custom-branding";
    /// Insurance claims, commission splits, payment schedules.
    public const string AdvancedBilling = "advanced-billing";
    /// SMS and WhatsApp reminders (email is on every plan).
    public const string SmsReminders = "sms-reminders";
    /// REST access with a tenant API key, and webhooks out.
    public const string ApiAccess = "api-access";
    /// Named account manager, 4-hour response, onboarding call.
    public const string PrioritySupport = "priority-support";

    public static readonly string[] All =
    {
        MultiBranch, AiAgents, PaymentGateways, InventoryPro, AdvancedAnalytics,
        PublicDirectory, EmbedWidget, CustomBranding, AdvancedBilling, SmsReminders,
        ApiAccess, PrioritySupport,
    };

    /// What the paywall tells the tenant they are missing. Keyed by code.
    public static string Describe(string feature) => feature switch
    {
        MultiBranch => "more than one branch",
        AiAgents => "the AI copilots",
        PaymentGateways => "taking card payments from your customers",
        InventoryPro => "purchase orders and supplier management",
        AdvancedAnalytics => "advanced analytics and exports",
        PublicDirectory => "your listing in the Unify directory",
        EmbedWidget => "the booking widget for your own website",
        CustomBranding => "custom forms and invoice branding",
        AdvancedBilling => "insurance claims, commissions and payment schedules",
        SmsReminders => "SMS and WhatsApp reminders",
        ApiAccess => "API access",
        PrioritySupport => "priority support",
        _ => feature,
    };
}
