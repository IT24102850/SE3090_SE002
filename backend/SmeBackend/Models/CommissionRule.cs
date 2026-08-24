namespace SmeBackend.Models;

public class CommissionRule : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public string Name { get; set; } = string.Empty;

    public string RuleType { get; set; } = "Percentage";

    public decimal Rate { get; set; }

    public decimal? FixedAmount { get; set; }

    public string? Description { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime? EffectiveFrom { get; set; }

    public DateTime? EffectiveTo { get; set; }
}
//tells the system how much commission should be calculated.