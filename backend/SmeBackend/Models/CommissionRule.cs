namespace SmeBackend.Models;

/// Tells the system how much commission is owed on a deal (real estate,
/// agents, referral partners). Rate is the percentage for RuleType
/// "Percentage"; FixedAmount is used for RuleType "Fixed". Min/MaxAmount
/// clamp the computed commission, and Role narrows the rule to one party
/// ("Agent", "Broker", "Referrer") when a deal is split between several.
public class CommissionRule : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public string Name { get; set; } = string.Empty;

    public string? Role { get; set; }

    public string RuleType { get; set; } = "Percentage";

    public decimal Rate { get; set; }

    public decimal? FixedAmount { get; set; }

    public decimal? MinAmount { get; set; }

    public decimal? MaxAmount { get; set; }

    public string? Description { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime? EffectiveFrom { get; set; }

    public DateTime? EffectiveTo { get; set; }
}
