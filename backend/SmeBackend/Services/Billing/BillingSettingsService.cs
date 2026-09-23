using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Services.Billing;

public interface IBillingSettingsService
{
    // Commission rules
    Task<IReadOnlyList<CommissionRuleResponse>> GetCommissionRulesAsync(Guid tenantId, bool activeOnly, CancellationToken ct = default);
    Task<BillingResult<CommissionRuleResponse>> UpsertCommissionRuleAsync(Guid tenantId, Guid? id, UpsertCommissionRuleRequest request, CancellationToken ct = default);
    Task<BillingResult<bool>> DeleteCommissionRuleAsync(Guid tenantId, Guid id, CancellationToken ct = default);
    Task<BillingResult<CommissionSplitResponse>> CalculateCommissionSplitAsync(Guid tenantId, CommissionSplitRequest request, CancellationToken ct = default);

    // Invoice templates
    Task<IReadOnlyList<InvoiceTemplateResponse>> GetTemplatesAsync(Guid tenantId, CancellationToken ct = default);
    Task<BillingResult<InvoiceTemplateResponse>> UpsertTemplateAsync(Guid tenantId, Guid? id, UpsertInvoiceTemplateRequest request, CancellationToken ct = default);
    Task<BillingResult<bool>> DeleteTemplateAsync(Guid tenantId, Guid id, CancellationToken ct = default);

    // Payment gateways
    Task<IReadOnlyList<PaymentGatewayResponse>> GetGatewaysAsync(Guid tenantId, CancellationToken ct = default);
    Task<BillingResult<PaymentGatewayResponse>> UpsertGatewayAsync(Guid tenantId, Guid? id, UpsertPaymentGatewayRequest request, string? publicBaseUrl, CancellationToken ct = default);
    Task<BillingResult<bool>> DeleteGatewayAsync(Guid tenantId, Guid id, CancellationToken ct = default);
    Task<BillingResult<GatewayTestResult>> TestGatewayAsync(Guid tenantId, Guid id, CancellationToken ct = default);
}

public sealed class BillingSettingsService : IBillingSettingsService
{
    public static readonly string[] BlockTypes =
        { "header", "businessInfo", "invoiceMeta", "customerInfo", "items", "totals", "payments", "notes", "footer" };

    private readonly AppDbContext _db;
    private readonly IPlatformSecretProtector _protector;
    private readonly IPaymentProcessorFactory _processors;

    public BillingSettingsService(AppDbContext db, IPlatformSecretProtector protector, IPaymentProcessorFactory processors)
    {
        _db = db;
        _protector = protector;
        _processors = processors;
    }

    // ==========================================
    // COMMISSION RULES
    // ==========================================

    public async Task<IReadOnlyList<CommissionRuleResponse>> GetCommissionRulesAsync(Guid tenantId, bool activeOnly, CancellationToken ct = default)
    {
        var q = _db.CommissionRules.AsNoTracking().Where(r => r.TenantId == tenantId);
        if (activeOnly) q = q.Where(r => r.IsActive);
        var rules = await q.OrderBy(r => r.Name).ToListAsync(ct);
        return rules.Select(MapRule).ToList();
    }

    public async Task<BillingResult<CommissionRuleResponse>> UpsertCommissionRuleAsync(Guid tenantId, Guid? id, UpsertCommissionRuleRequest request, CancellationToken ct = default)
    {
        var type = request.RuleType?.Trim();
        if (!string.Equals(type, "Percentage", StringComparison.OrdinalIgnoreCase) && !string.Equals(type, "Fixed", StringComparison.OrdinalIgnoreCase))
            return BillingResult<CommissionRuleResponse>.BadRequest("RuleType must be Percentage or Fixed.");
        type = char.ToUpperInvariant(type![0]) + type[1..].ToLowerInvariant();
        if (type == "Percentage" && (request.Rate <= 0 || request.Rate > 100))
            return BillingResult<CommissionRuleResponse>.BadRequest("A percentage rule needs a rate between 0 and 100.");
        if (type == "Fixed" && (request.FixedAmount is null || request.FixedAmount <= 0))
            return BillingResult<CommissionRuleResponse>.BadRequest("A fixed rule needs a FixedAmount above 0.");
        if (request.MinAmount is { } min && request.MaxAmount is { } max && min > max)
            return BillingResult<CommissionRuleResponse>.BadRequest("MinAmount cannot be above MaxAmount.");
        if (request.EffectiveFrom is { } f && request.EffectiveTo is { } t && t < f)
            return BillingResult<CommissionRuleResponse>.BadRequest("EffectiveTo cannot be before EffectiveFrom.");

        var name = request.Name.Trim();
        if (await _db.CommissionRules.AnyAsync(r => r.TenantId == tenantId && r.Name == name && r.Id != id, ct))
            return BillingResult<CommissionRuleResponse>.Conflict($"A commission rule named '{name}' already exists.");

        CommissionRule rule;
        if (id is { } existingId)
        {
            var found = await _db.CommissionRules.FirstOrDefaultAsync(r => r.Id == existingId && r.TenantId == tenantId, ct);
            if (found is null) return BillingResult<CommissionRuleResponse>.NotFound("Commission rule not found.");
            rule = found;
        }
        else
        {
            rule = new CommissionRule { TenantId = tenantId };
            _db.CommissionRules.Add(rule);
        }

        rule.Name = name;
        rule.RuleType = type;
        rule.Rate = type == "Percentage" ? request.Rate : 0;
        rule.FixedAmount = type == "Fixed" ? request.FixedAmount : null;
        rule.MinAmount = request.MinAmount;
        rule.MaxAmount = request.MaxAmount;
        rule.Role = string.IsNullOrWhiteSpace(request.Role) ? null : request.Role.Trim();
        rule.Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
        rule.IsActive = request.IsActive;
        rule.EffectiveFrom = request.EffectiveFrom;
        rule.EffectiveTo = request.EffectiveTo;
        rule.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return id is null ? BillingResult<CommissionRuleResponse>.Created(MapRule(rule)) : BillingResult<CommissionRuleResponse>.Ok(MapRule(rule));
    }

    public async Task<BillingResult<bool>> DeleteCommissionRuleAsync(Guid tenantId, Guid id, CancellationToken ct = default)
    {
        var rule = await _db.CommissionRules.FirstOrDefaultAsync(r => r.Id == id && r.TenantId == tenantId, ct);
        if (rule is null) return BillingResult<bool>.NotFound("Commission rule not found.");
        _db.CommissionRules.Remove(rule);
        await _db.SaveChangesAsync(ct);
        return BillingResult<bool>.Ok(true);
    }

    public async Task<BillingResult<CommissionSplitResponse>> CalculateCommissionSplitAsync(Guid tenantId, CommissionSplitRequest request, CancellationToken ct = default)
    {
        if (request.DealAmount <= 0) return BillingResult<CommissionSplitResponse>.BadRequest("DealAmount must be greater than 0.");

        var asOf = request.AsOf ?? DateTime.UtcNow;
        var rules = await ActiveRulesAsync(tenantId, asOf, ct);
        if (request.Roles is { Count: > 0 } roles)
        {
            var wanted = roles.Select(r => r.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
            rules = rules.Where(r => r.Role is not null && wanted.Contains(r.Role)).ToList();
        }

        var lines = rules.Select(r =>
        {
            var (amount, clamped) = BillingRules.ApplyCommissionRule(request.DealAmount, r.RuleType, r.Rate, r.FixedAmount, r.MinAmount, r.MaxAmount);
            return new CommissionSplitLine(r.Id, r.Name, r.Role, r.RuleType, r.Rate, amount, clamped);
        }).ToList();

        var total = lines.Sum(l => l.Amount);
        return BillingResult<CommissionSplitResponse>.Ok(new CommissionSplitResponse(
            BillingRules.Round(request.DealAmount), lines, BillingRules.Round(total), BillingRules.Round(request.DealAmount - total)));
    }

    public async Task<List<CommissionRule>> ActiveRulesAsync(Guid tenantId, DateTime asOf, CancellationToken ct) =>
        await _db.CommissionRules.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.IsActive)
            .Where(r => (r.EffectiveFrom == null || r.EffectiveFrom <= asOf) && (r.EffectiveTo == null || r.EffectiveTo >= asOf))
            .OrderBy(r => r.Name)
            .ToListAsync(ct);

    private static CommissionRuleResponse MapRule(CommissionRule r) =>
        new(r.Id, r.Name, r.Role, r.RuleType, r.Rate, r.FixedAmount, r.MinAmount, r.MaxAmount, r.Description, r.IsActive,
            r.EffectiveFrom, r.EffectiveTo);

    // ==========================================
    // INVOICE TEMPLATES
    // ==========================================

    public async Task<IReadOnlyList<InvoiceTemplateResponse>> GetTemplatesAsync(Guid tenantId, CancellationToken ct = default)
    {
        var templates = await _db.InvoiceTemplates.AsNoTracking()
            .Where(t => t.TenantId == tenantId)
            .OrderByDescending(t => t.IsDefault).ThenBy(t => t.Name)
            .ToListAsync(ct);
        return templates.Select(MapTemplate).ToList();
    }

    public async Task<BillingResult<InvoiceTemplateResponse>> UpsertTemplateAsync(Guid tenantId, Guid? id, UpsertInvoiceTemplateRequest request, CancellationToken ct = default)
    {
        var layoutError = ValidateLayout(request.Layout);
        if (layoutError is not null) return BillingResult<InvoiceTemplateResponse>.BadRequest(layoutError);
        if (ReceiptPdfBuilder.ParseColor(request.AccentColor) is null)
            return BillingResult<InvoiceTemplateResponse>.BadRequest("AccentColor must be a hex colour such as #2563eb.");

        var name = request.Name.Trim();
        if (await _db.InvoiceTemplates.AnyAsync(t => t.TenantId == tenantId && t.Name == name && t.Id != id, ct))
            return BillingResult<InvoiceTemplateResponse>.Conflict($"A template named '{name}' already exists.");

        InvoiceTemplate template;
        if (id is { } existingId)
        {
            var found = await _db.InvoiceTemplates.FirstOrDefaultAsync(t => t.Id == existingId && t.TenantId == tenantId, ct);
            if (found is null) return BillingResult<InvoiceTemplateResponse>.NotFound("Template not found.");
            template = found;
        }
        else
        {
            template = new InvoiceTemplate { TenantId = tenantId };
            _db.InvoiceTemplates.Add(template);
        }

        // Exactly one default per tenant; the first template is the default.
        var isFirst = !await _db.InvoiceTemplates.AnyAsync(t => t.TenantId == tenantId && t.Id != template.Id, ct);
        var makeDefault = request.IsDefault || isFirst;
        if (makeDefault)
        {
            var others = await _db.InvoiceTemplates.Where(t => t.TenantId == tenantId && t.IsDefault && t.Id != template.Id).ToListAsync(ct);
            foreach (var other in others) other.IsDefault = false;
        }

        template.Name = name;
        template.LayoutJson = request.Layout.GetRawText();
        template.AccentColor = request.AccentColor.Trim();
        template.HeaderText = string.IsNullOrWhiteSpace(request.HeaderText) ? null : request.HeaderText.Trim();
        template.FooterText = string.IsNullOrWhiteSpace(request.FooterText) ? null : request.FooterText.Trim();
        // A default is replaced by marking another template default, never unset.
        template.IsDefault = makeDefault || template.IsDefault;
        template.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return id is null ? BillingResult<InvoiceTemplateResponse>.Created(MapTemplate(template)) : BillingResult<InvoiceTemplateResponse>.Ok(MapTemplate(template));
    }

    public async Task<BillingResult<bool>> DeleteTemplateAsync(Guid tenantId, Guid id, CancellationToken ct = default)
    {
        var template = await _db.InvoiceTemplates.FirstOrDefaultAsync(t => t.Id == id && t.TenantId == tenantId, ct);
        if (template is null) return BillingResult<bool>.NotFound("Template not found.");

        _db.InvoiceTemplates.Remove(template);
        if (template.IsDefault)
        {
            var next = await _db.InvoiceTemplates.Where(t => t.TenantId == tenantId && t.Id != id).OrderBy(t => t.CreatedAt).FirstOrDefaultAsync(ct);
            if (next is not null) next.IsDefault = true;
        }
        await _db.SaveChangesAsync(ct);
        return BillingResult<bool>.Ok(true);
    }

    public static string? ValidateLayout(JsonElement layout)
    {
        if (layout.ValueKind != JsonValueKind.Array) return "Layout must be a JSON array of blocks.";
        var seen = new HashSet<string>();
        var count = 0;
        foreach (var block in layout.EnumerateArray())
        {
            if (++count > 30) return "A layout can have at most 30 blocks.";
            if (block.ValueKind != JsonValueKind.Object) return "Every layout block must be an object.";
            if (!block.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String)
                return "Every layout block needs a 'type'.";
            var t = type.GetString()!;
            if (!BlockTypes.Contains(t)) return $"Unknown block type '{t}'. Allowed: {string.Join(", ", BlockTypes)}.";
            if (!seen.Add(t)) return $"Block '{t}' appears more than once.";
        }
        return null;
    }

    public static InvoiceTemplateResponse MapTemplate(InvoiceTemplate t)
    {
        JsonElement layout;
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(t.LayoutJson) ? "[]" : t.LayoutJson);
            layout = doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            using var empty = JsonDocument.Parse("[]");
            layout = empty.RootElement.Clone();
        }
        return new InvoiceTemplateResponse(t.Id, t.Name, t.IsDefault, layout, t.AccentColor, t.HeaderText, t.FooterText, t.UpdatedAt);
    }

    // ==========================================
    // PAYMENT GATEWAYS
    // ==========================================

    public async Task<IReadOnlyList<PaymentGatewayResponse>> GetGatewaysAsync(Guid tenantId, CancellationToken ct = default)
    {
        var gateways = await _db.PaymentGateways.AsNoTracking()
            .Where(g => g.TenantId == tenantId)
            .OrderByDescending(g => g.IsActive).ThenBy(g => g.Name)
            .ToListAsync(ct);
        return gateways.Select(MapGateway).ToList();
    }

    public async Task<BillingResult<PaymentGatewayResponse>> UpsertGatewayAsync(Guid tenantId, Guid? id, UpsertPaymentGatewayRequest request, string? publicBaseUrl, CancellationToken ct = default)
    {
        var provider = PaymentProviders.Normalize(request.Provider);
        if (provider is null)
            return BillingResult<PaymentGatewayResponse>.BadRequest($"Provider must be one of: {string.Join(", ", PaymentProviders.All)}.");

        if (provider == PaymentProviders.Stripe && request.PublicKey?.Trim().StartsWith("sk_") == true)
            return BillingResult<PaymentGatewayResponse>.BadRequest("That looks like a Stripe secret key - put it in ApiKey, not PublicKey.");

        var name = request.Name.Trim();
        if (await _db.PaymentGateways.AnyAsync(g => g.TenantId == tenantId && g.Name == name && g.Id != id, ct))
            return BillingResult<PaymentGatewayResponse>.Conflict($"A gateway named '{name}' already exists.");

        PaymentGateway gateway;
        if (id is { } existingId)
        {
            var found = await _db.PaymentGateways.FirstOrDefaultAsync(g => g.Id == existingId && g.TenantId == tenantId, ct);
            if (found is null) return BillingResult<PaymentGatewayResponse>.NotFound("Payment gateway not found.");
            gateway = found;
        }
        else
        {
            gateway = new PaymentGateway { TenantId = tenantId };
            _db.PaymentGateways.Add(gateway);
        }

        gateway.Name = name;
        gateway.Provider = provider;
        gateway.Currency = string.IsNullOrWhiteSpace(request.Currency) ? "LKR" : request.Currency.Trim().ToUpperInvariant();
        gateway.IsActive = request.IsActive;
        gateway.IsTestMode = request.IsTestMode;
        gateway.PublicKey = string.IsNullOrWhiteSpace(request.PublicKey) ? null : request.PublicKey.Trim();

        // null keeps the stored secret, "" clears it, anything else replaces it.
        if (request.ApiKey is not null)
            gateway.ApiKeyEncrypted = request.ApiKey.Trim().Length == 0 ? null : _protector.Protect(request.ApiKey.Trim());
        if (request.WebhookSecret is not null)
            gateway.WebhookSecretEncrypted = request.WebhookSecret.Trim().Length == 0 ? null : _protector.Protect(request.WebhookSecret.Trim());

        gateway.WebhookUrl = provider == PaymentProviders.Manual || string.IsNullOrWhiteSpace(publicBaseUrl)
            ? null
            : $"{publicBaseUrl.TrimEnd('/')}/api/payments/webhooks/{provider.ToLowerInvariant()}/{tenantId}";
        gateway.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return id is null ? BillingResult<PaymentGatewayResponse>.Created(MapGateway(gateway)) : BillingResult<PaymentGatewayResponse>.Ok(MapGateway(gateway));
    }

    public async Task<BillingResult<bool>> DeleteGatewayAsync(Guid tenantId, Guid id, CancellationToken ct = default)
    {
        var gateway = await _db.PaymentGateways.FirstOrDefaultAsync(g => g.Id == id && g.TenantId == tenantId, ct);
        if (gateway is null) return BillingResult<bool>.NotFound("Payment gateway not found.");
        _db.PaymentGateways.Remove(gateway);
        await _db.SaveChangesAsync(ct);
        return BillingResult<bool>.Ok(true);
    }

    public async Task<BillingResult<GatewayTestResult>> TestGatewayAsync(Guid tenantId, Guid id, CancellationToken ct = default)
    {
        var gateway = await _db.PaymentGateways.AsNoTracking().FirstOrDefaultAsync(g => g.Id == id && g.TenantId == tenantId, ct);
        if (gateway is null) return BillingResult<GatewayTestResult>.NotFound("Payment gateway not found.");

        try
        {
            var (ok, message) = await _processors.Get(gateway.Provider).TestConnectionAsync(Credentials(gateway), ct);
            return BillingResult<GatewayTestResult>.Ok(new GatewayTestResult(ok, gateway.Provider == PaymentProviders.Manual, message));
        }
        catch (PaymentProviderException ex)
        {
            return BillingResult<GatewayTestResult>.Ok(new GatewayTestResult(false, false, ex.Message));
        }
        catch (HttpRequestException)
        {
            return BillingResult<GatewayTestResult>.Ok(new GatewayTestResult(false, false, $"{gateway.Provider} could not be reached."));
        }
    }

    public GatewayCredentials Credentials(PaymentGateway g) => new(
        g.Provider,
        g.ApiKeyEncrypted is null ? null : _protector.Unprotect(g.ApiKeyEncrypted),
        g.PublicKey,
        g.WebhookSecretEncrypted is null ? null : _protector.Unprotect(g.WebhookSecretEncrypted),
        g.IsTestMode);

    private PaymentGatewayResponse MapGateway(PaymentGateway g)
    {
        string? hint = null;
        if (g.ApiKeyEncrypted is not null)
        {
            try
            {
                var key = _protector.Unprotect(g.ApiKeyEncrypted);
                hint = key.Length <= 4 ? "••••" : $"••••{key[^4..]}";
            }
            catch
            {
                hint = "•••• (unreadable - re-enter the key)";
            }
        }
        return new PaymentGatewayResponse(g.Id, g.Name, g.Provider, g.Currency, g.IsActive, g.IsTestMode, g.PublicKey,
            g.ApiKeyEncrypted is not null, hint, g.WebhookSecretEncrypted is not null, g.WebhookUrl, g.CreatedAt, g.UpdatedAt);
    }
}
