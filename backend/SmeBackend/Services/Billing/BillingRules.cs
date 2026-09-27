using System.Text.RegularExpressions;
using SmeBackend.DTOs;

namespace SmeBackend.Services.Billing;

/// The business rules the billing agent validates against - shared by the
/// agent's tools, the invoice pre-check endpoint and the approval gates, so
/// "what counts as suspicious" is defined in exactly one place.
public static class BillingRules
{
    private static readonly Regex PolicyNumberPattern = new("^[A-Za-z0-9][A-Za-z0-9/-]{3,39}$", RegexOptions.Compiled);

    public readonly record struct DraftLine(int Quantity, decimal UnitPrice);

    public static decimal Round(decimal value) => Math.Round(value, 2, MidpointRounding.AwayFromZero);

    /// Discount as a share of the item subtotal, 0-100 (100 for a discount
    /// on a zero subtotal, which is always suspicious).
    public static decimal DiscountPercent(decimal subtotal, decimal discount)
    {
        if (discount <= 0) return 0;
        if (subtotal <= 0) return 100;
        return Round(discount / subtotal * 100m);
    }

    /// Tax as a share of the discounted subtotal.
    public static decimal TaxPercent(decimal subtotal, decimal discount, decimal tax)
    {
        var taxable = subtotal - discount;
        if (tax <= 0) return 0;
        if (taxable <= 0) return 100;
        return Round(tax / taxable * 100m);
    }

    /// Invoice schema + business-rule validation for a draft (or an issued
    /// invoice being re-checked). Errors make the invoice invalid; warnings
    /// flag it for human review but do not block it.
    public static InvoiceValidationResult ValidateInvoice(
        IReadOnlyCollection<DraftLine> lines,
        decimal discount,
        decimal tax,
        ThresholdConfig? thresholds = null)
    {
        var t = thresholds ?? ThresholdConfig.Default;
        var issues = new List<InvoiceValidationIssue>();

        if (lines.Count == 0)
            issues.Add(new("no_items", "error", "An invoice must contain at least one item."));

        foreach (var line in lines)
        {
            if (line.Quantity <= 0)
                issues.Add(new("invalid_quantity", "error", "Every item quantity must be greater than 0."));
            if (line.UnitPrice < 0)
                issues.Add(new("negative_price", "error", "Item prices cannot be negative."));
        }

        if (discount < 0) issues.Add(new("negative_discount", "error", "Discount cannot be negative."));
        if (tax < 0) issues.Add(new("negative_tax", "error", "Tax cannot be negative."));

        var subtotal = Round(lines.Sum(l => Round(l.Quantity * l.UnitPrice)));
        var discountPercent = DiscountPercent(subtotal, discount);
        var taxPercent = TaxPercent(subtotal, discount, tax);
        var final = Math.Max(0, Round(subtotal - discount + tax));

        if (discount > subtotal && discount > 0)
        {
            issues.Add(new("discount_exceeds_subtotal", "error",
                $"Discount ({discount:N2}) is larger than the item subtotal ({subtotal:N2})."));
        }
        else if (discountPercent > t.MaxDiscountPercent)
        {
            issues.Add(new("excessive_discount", "warning",
                $"Discount is {discountPercent:0.##}% of the subtotal, above the {t.MaxDiscountPercent:0.##}% cap - needs review."));
        }

        if (tax > 0 && (taxPercent < t.MinTaxPercent || taxPercent > t.MaxTaxPercent))
        {
            issues.Add(new("tax_out_of_range", "warning",
                $"Tax is {taxPercent:0.##}% of the taxable amount, outside the {t.MinTaxPercent:0.##}-{t.MaxTaxPercent:0.##}% range."));
        }
        else if (tax == 0 && t.MinTaxPercent > 0 && subtotal - discount > 0)
        {
            issues.Add(new("missing_tax", "warning",
                $"No tax was charged, but the minimum tax rate is {t.MinTaxPercent:0.##}%."));
        }

        if (subtotal > 0 && final == 0)
            issues.Add(new("zero_total", "warning", "The invoice has priced items but a payable amount of zero."));

        if (final >= t.HighValueInvoiceAmount)
            issues.Add(new("high_value_invoice", "warning", $"Payable amount {final:N2} is above the high-value threshold."));

        var hasErrors = issues.Any(i => i.Severity == "error");
        var requiresReview = issues.Any(i => i.Severity is "warning" or "error");

        return new InvoiceValidationResult(!hasErrors, requiresReview, subtotal, discountPercent, taxPercent, final, issues);
    }

    public readonly record struct ClaimContext(
        decimal ClaimAmount,
        string Provider,
        string PolicyNumber,
        decimal InvoiceFinalAmount,
        string InvoiceStatus,
        decimal OtherClaimsTotal,
        string? CustomerInsuranceProvider,
        string? CustomerInsuranceNumber);

    /// Insurance policy rule matching for one claim.
    public static ClaimValidationResult ValidateClaim(ClaimContext c, ThresholdConfig? thresholds = null)
    {
        var t = thresholds ?? ThresholdConfig.Default;
        var issues = new List<InvoiceValidationIssue>();

        if (c.ClaimAmount <= 0)
            issues.Add(new("invalid_amount", "error", "The claim amount must be greater than 0."));
        if (string.IsNullOrWhiteSpace(c.Provider))
            issues.Add(new("missing_provider", "error", "The insurance provider is required."));
        if (string.IsNullOrWhiteSpace(c.PolicyNumber) || !PolicyNumberPattern.IsMatch(c.PolicyNumber.Trim()))
            issues.Add(new("invalid_policy_number", "error", "The policy number must be 4-40 letters, digits, '/' or '-'."));
        if (c.InvoiceStatus.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))
            issues.Add(new("invoice_cancelled", "error", "Claims cannot be made against a cancelled invoice."));

        if (c.ClaimAmount > c.InvoiceFinalAmount)
        {
            issues.Add(new("claim_exceeds_invoice", "error",
                $"The claim ({c.ClaimAmount:N2}) is larger than the invoice ({c.InvoiceFinalAmount:N2})."));
        }
        else if (c.ClaimAmount + c.OtherClaimsTotal > c.InvoiceFinalAmount)
        {
            issues.Add(new("claims_exceed_invoice", "error",
                $"Together with {c.OtherClaimsTotal:N2} already claimed, this claim exceeds the invoice amount."));
        }

        if (!string.IsNullOrWhiteSpace(c.CustomerInsuranceProvider) &&
            !string.IsNullOrWhiteSpace(c.Provider) &&
            !c.CustomerInsuranceProvider.Trim().Equals(c.Provider.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            issues.Add(new("provider_mismatch", "warning",
                $"The patient's profile lists '{c.CustomerInsuranceProvider}' as their insurer, not '{c.Provider}'."));
        }

        if (!string.IsNullOrWhiteSpace(c.CustomerInsuranceNumber) &&
            !string.IsNullOrWhiteSpace(c.PolicyNumber) &&
            !c.CustomerInsuranceNumber.Trim().Equals(c.PolicyNumber.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            issues.Add(new("policy_mismatch", "warning",
                "The policy number does not match the one on the patient's profile."));
        }

        var isValid = issues.All(i => i.Severity != "error");
        return new ClaimValidationResult(isValid, c.ClaimAmount > t.ClaimApprovalAmount, issues);
    }

    /// Spec 3.7 human-approval rules.
    public static bool AdjustmentRequiresApproval(decimal changeInPayable, ThresholdConfig? t = null)
        => Math.Abs(changeInPayable) > (t ?? ThresholdConfig.Default).AdjustmentApprovalAmount;

    public static bool ClaimRequiresApproval(decimal claimAmount, ThresholdConfig? t = null)
        => claimAmount > (t ?? ThresholdConfig.Default).ClaimApprovalAmount;

    public static bool CancellationRequiresApproval(decimal refundAmount) => refundAmount > 0;

    /// Clamp one rule's commission to its min/max.
    public static (decimal Amount, bool Clamped) ApplyCommissionRule(
        decimal dealAmount, string ruleType, decimal rate, decimal? fixedAmount, decimal? min, decimal? max)
    {
        var raw = ruleType.Equals("Fixed", StringComparison.OrdinalIgnoreCase)
            ? fixedAmount ?? 0
            : dealAmount * rate / 100m;
        var amount = Round(raw);
        var clamped = false;
        if (min.HasValue && amount < min.Value) { amount = min.Value; clamped = true; }
        if (max.HasValue && amount > max.Value) { amount = max.Value; clamped = true; }
        return (amount, clamped);
    }
}
