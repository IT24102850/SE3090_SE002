using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using System.Text.RegularExpressions;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services;

public class DynamicFormService : IDynamicFormService
{
    private readonly AppDbContext _db;

    public DynamicFormService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<(bool Found, DynamicFormValidationResponse Response)> ValidateFormAsync(
        Guid tenantId,
        string formType,
        JsonElement data,
        CancellationToken cancellationToken = default)
    {
        var form = await _db.DynamicForms
            .AsNoTracking()
            .FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == formType, cancellationToken);

        if (form == null)
        {
            return (false, new DynamicFormValidationResponse(false, new List<DynamicFormValidationError>
            {
                new("formType", $"Dynamic form with type '{formType}' not found for the current tenant.")
            }));
        }

        var errors = ValidateDataAgainstSchema(data, form.SchemaJson, form.ValidationRulesJson);
        var isValid = errors.Count == 0;

        return (true, new DynamicFormValidationResponse(isValid, errors));
    }

    public async Task<(bool Found, bool IsValid, string? Error, IReadOnlyList<DynamicFormValidationError>? ValidationErrors, FormSubmissionResponse? Submission)> SubmitFormAsync(
        Guid tenantId,
        string formType,
        DynamicFormSubmitRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.EntityId == Guid.Empty)
        {
            return (true, false, "Valid EntityId is required.", null, null);
        }

        var form = await _db.DynamicForms
            .FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == formType, cancellationToken);

        if (form == null)
        {
            return (false, false, $"Dynamic form with type '{formType}' not found.", null, null);
        }

        var errors = ValidateDataAgainstSchema(request.Data, form.SchemaJson, form.ValidationRulesJson);
        if (errors.Count > 0)
        {
            return (true, false, "Form validation failed.", errors, null);
        }

        var rawJson = request.Data.ValueKind switch
        {
            JsonValueKind.Undefined or JsonValueKind.Null => "{}",
            _ => request.Data.GetRawText()
        };

        var submission = new FormSubmission
        {
            DynamicFormId = form.Id,
            EntityId = request.EntityId,
            DataJson = rawJson,
            SubmittedAt = DateTime.UtcNow
        };

        _db.FormSubmissions.Add(submission);
        await _db.SaveChangesAsync(cancellationToken);

        using var doc = JsonDocument.Parse(submission.DataJson);
        var response = new FormSubmissionResponse(
            submission.Id,
            submission.DynamicFormId,
            form.FormType,
            submission.EntityId,
            doc.RootElement.Clone(),
            submission.SubmittedAt,
            submission.CreatedAt
        );

        return (true, true, null, null, response);
    }

    // ==========================================
    // FORM BUILDER
    // ==========================================

    private static readonly Regex FormTypePattern = new("^[a-z0-9][a-z0-9_-]{1,99}$", RegexOptions.Compiled);

    public static readonly string[] FieldTypes = { "string", "number", "integer", "boolean", "array", "object" };

    public async Task<IReadOnlyList<DynamicFormResponse>> GetFormsAsync(Guid tenantId, CancellationToken ct = default)
    {
        var forms = await _db.DynamicForms.AsNoTracking()
            .Where(f => f.TenantId == tenantId)
            .OrderBy(f => f.FormType)
            .ToListAsync(ct);
        var ids = forms.Select(f => (Guid?)f.Id).ToList();
        var counts = await _db.FormSubmissions.AsNoTracking()
            .Where(s => ids.Contains(s.DynamicFormId))
            .GroupBy(s => s.DynamicFormId)
            .Select(g => new { Id = g.Key, Count = g.Count() })
            .ToListAsync(ct);
        return forms.Select(f => MapForm(f, counts.FirstOrDefault(c => c.Id == f.Id)?.Count ?? 0)).ToList();
    }

    public async Task<BillingResult<DynamicFormResponse>> GetFormAsync(Guid tenantId, string formType, CancellationToken ct = default)
    {
        var form = await _db.DynamicForms.AsNoTracking().FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == formType, ct);
        if (form is null) return BillingResult<DynamicFormResponse>.NotFound($"Dynamic form '{formType}' not found.");
        var count = await _db.FormSubmissions.CountAsync(s => s.DynamicFormId == form.Id, ct);
        return BillingResult<DynamicFormResponse>.Ok(MapForm(form, count));
    }

    public async Task<BillingResult<DynamicFormResponse>> UpsertFormAsync(Guid tenantId, string formType, UpsertDynamicFormRequest request, CancellationToken ct = default)
    {
        var type = formType?.Trim().ToLowerInvariant() ?? "";
        if (!FormTypePattern.IsMatch(type))
            return BillingResult<DynamicFormResponse>.BadRequest("Form type must be 2-100 lowercase letters, digits, '-' or '_'.");

        var schemaError = ValidateSchemaDefinition(request.Schema);
        if (schemaError is not null) return BillingResult<DynamicFormResponse>.BadRequest(schemaError);
        if (request.UiSchema is { } ui && ui.ValueKind is not (JsonValueKind.Object or JsonValueKind.Null or JsonValueKind.Undefined))
            return BillingResult<DynamicFormResponse>.BadRequest("UiSchema must be a JSON object.");
        if (request.ValidationRules is { } rules && rules.ValueKind is not (JsonValueKind.Object or JsonValueKind.Null or JsonValueKind.Undefined))
            return BillingResult<DynamicFormResponse>.BadRequest("ValidationRules must be a JSON object.");

        var form = await _db.DynamicForms.FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == type, ct);
        var created = form is null;
        if (form is null)
        {
            form = new DynamicForm { TenantId = tenantId, FormType = type };
            _db.DynamicForms.Add(form);
        }

        form.SchemaJson = request.Schema.GetRawText();
        form.UiSchemaJson = request.UiSchema is { ValueKind: JsonValueKind.Object } u ? u.GetRawText() : null;
        form.ValidationRulesJson = request.ValidationRules is { ValueKind: JsonValueKind.Object } r ? r.GetRawText() : null;
        form.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        var count = created ? 0 : await _db.FormSubmissions.CountAsync(s => s.DynamicFormId == form.Id, ct);
        return created ? BillingResult<DynamicFormResponse>.Created(MapForm(form, count)) : BillingResult<DynamicFormResponse>.Ok(MapForm(form, count));
    }

    public async Task<BillingResult<bool>> DeleteFormAsync(Guid tenantId, string formType, CancellationToken ct = default)
    {
        var form = await _db.DynamicForms.FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == formType, ct);
        if (form is null) return BillingResult<bool>.NotFound($"Dynamic form '{formType}' not found.");
        // Submissions keep their data; the FK is SET NULL.
        _db.DynamicForms.Remove(form);
        await _db.SaveChangesAsync(ct);
        return BillingResult<bool>.Ok(true);
    }

    public async Task<BillingResult<IReadOnlyList<FormSubmissionResponse>>> GetSubmissionsAsync(Guid tenantId, string formType, Guid? entityId, int take, CancellationToken ct = default)
    {
        var form = await _db.DynamicForms.AsNoTracking().FirstOrDefaultAsync(f => f.TenantId == tenantId && f.FormType == formType, ct);
        if (form is null) return BillingResult<IReadOnlyList<FormSubmissionResponse>>.NotFound($"Dynamic form '{formType}' not found.");

        var q = _db.FormSubmissions.AsNoTracking().Where(s => s.DynamicFormId == form.Id);
        if (entityId is { } e) q = q.Where(s => s.EntityId == e);
        var rows = await q.OrderByDescending(s => s.SubmittedAt).Take(Math.Clamp(take, 1, 200)).ToListAsync(ct);

        return BillingResult<IReadOnlyList<FormSubmissionResponse>>.Ok(rows.Select(s =>
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(s.DataJson) ? "{}" : s.DataJson);
            return new FormSubmissionResponse(s.Id, s.DynamicFormId, form.FormType, s.EntityId, doc.RootElement.Clone(), s.SubmittedAt, s.CreatedAt);
        }).ToList());
    }

    /// Structural check of a form definition (not of submitted data): a JSON
    /// Schema object whose properties use supported types, and whose
    /// "required" names only fields it defines.
    public static string? ValidateSchemaDefinition(JsonElement schema)
    {
        if (schema.ValueKind != JsonValueKind.Object) return "Schema must be a JSON object.";
        if (schema.TryGetProperty("type", out var rootType) && rootType.ValueKind == JsonValueKind.String && rootType.GetString() != "object")
            return "The schema's root type must be 'object'.";
        if (!schema.TryGetProperty("properties", out var props) || props.ValueKind != JsonValueKind.Object)
            return "Schema must define 'properties'.";

        var names = new HashSet<string>();
        foreach (var prop in props.EnumerateObject())
        {
            names.Add(prop.Name);
            if (prop.Value.ValueKind != JsonValueKind.Object) return $"Field '{prop.Name}' must be an object.";
            if (!prop.Value.TryGetProperty("type", out var t) || t.ValueKind != JsonValueKind.String || !FieldTypes.Contains(t.GetString()))
                return $"Field '{prop.Name}' needs a type: {string.Join(", ", FieldTypes)}.";
            if (prop.Value.TryGetProperty("enum", out var e) && (e.ValueKind != JsonValueKind.Array || e.GetArrayLength() == 0))
                return $"Field '{prop.Name}' has an empty or invalid enum.";
        }
        if (names.Count == 0) return "Schema must define at least one field.";
        if (names.Count > 100) return "A form can have at most 100 fields.";

        if (schema.TryGetProperty("required", out var req))
        {
            if (req.ValueKind != JsonValueKind.Array) return "'required' must be an array of field names.";
            foreach (var r in req.EnumerateArray())
            {
                if (r.ValueKind != JsonValueKind.String || !names.Contains(r.GetString()!))
                    return $"Required field '{r}' is not defined in properties.";
            }
        }
        return null;
    }

    private static DynamicFormResponse MapForm(DynamicForm f, int submissions)
    {
        static JsonElement? Parse(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            try
            {
                using var doc = JsonDocument.Parse(json);
                return doc.RootElement.Clone();
            }
            catch (JsonException)
            {
                return null;
            }
        }

        return new DynamicFormResponse(f.Id, f.FormType, Parse(f.SchemaJson) ?? default, Parse(f.UiSchemaJson), Parse(f.ValidationRulesJson),
            submissions, f.CreatedAt, f.UpdatedAt);
    }

    public static List<DynamicFormValidationError> ValidateDataAgainstSchema(
        JsonElement data,
        string schemaJson,
        string? validationRulesJson)
    {
        var errors = new List<DynamicFormValidationError>();

        if (data.ValueKind != JsonValueKind.Object)
        {
            errors.Add(new DynamicFormValidationError("$", "Submitted form data must be a valid JSON object."));
            return errors;
        }

        if (string.IsNullOrWhiteSpace(schemaJson))
        {
            return errors;
        }

        try
        {
            using var schemaDoc = JsonDocument.Parse(schemaJson);
            var root = schemaDoc.RootElement;

            // 1. Required fields
            if (root.TryGetProperty("required", out var requiredProp) && requiredProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var reqItem in requiredProp.EnumerateArray())
                {
                    if (reqItem.ValueKind == JsonValueKind.String)
                    {
                        var reqFieldName = reqItem.GetString();
                        if (!string.IsNullOrEmpty(reqFieldName))
                        {
                            if (!data.TryGetProperty(reqFieldName, out var propVal) ||
                                propVal.ValueKind == JsonValueKind.Null ||
                                propVal.ValueKind == JsonValueKind.Undefined ||
                                (propVal.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(propVal.GetString())))
                            {
                                errors.Add(new DynamicFormValidationError(reqFieldName, $"Field '{reqFieldName}' is required."));
                            }
                        }
                    }
                }
            }

            // 2. Property types and constraints
            if (root.TryGetProperty("properties", out var properties) && properties.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in properties.EnumerateObject())
                {
                    var fieldName = prop.Name;
                    var fieldSchema = prop.Value;

                    if (data.TryGetProperty(fieldName, out var submittedValue) &&
                        submittedValue.ValueKind != JsonValueKind.Null &&
                        submittedValue.ValueKind != JsonValueKind.Undefined)
                    {
                        ValidateField(fieldName, submittedValue, fieldSchema, errors);
                    }
                }
            }
        }
        catch (JsonException ex)
        {
            errors.Add(new DynamicFormValidationError("$schema", $"Invalid schema configuration: {ex.Message}"));
        }

        // 3. Optional validation rules (e.g. custom rules JSON)
        if (!string.IsNullOrWhiteSpace(validationRulesJson))
        {
            try
            {
                using var rulesDoc = JsonDocument.Parse(validationRulesJson);
                var rulesRoot = rulesDoc.RootElement;
                if (rulesRoot.ValueKind == JsonValueKind.Object)
                {
                    foreach (var ruleProp in rulesRoot.EnumerateObject())
                    {
                        var fieldName = ruleProp.Name;
                        if (data.TryGetProperty(fieldName, out var submittedVal))
                        {
                            ValidateCustomRules(fieldName, submittedVal, ruleProp.Value, errors);
                        }
                    }
                }
            }
            catch
            {
                // Ignore malformed custom rules
            }
        }

        return errors;
    }

    private static void ValidateField(
        string fieldName,
        JsonElement value,
        JsonElement schema,
        List<DynamicFormValidationError> errors)
    {
        if (schema.TryGetProperty("type", out var typeProp) && typeProp.ValueKind == JsonValueKind.String)
        {
            var expectedType = typeProp.GetString()?.ToLowerInvariant();
            switch (expectedType)
            {
                case "string":
                    if (value.ValueKind != JsonValueKind.String)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be a string."));
                        return;
                    }
                    var strVal = value.GetString() ?? "";
                    if (schema.TryGetProperty("minLength", out var minLen) && minLen.TryGetInt32(out var minLenVal) && strVal.Length < minLenVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be at least {minLenVal} characters."));
                    }
                    if (schema.TryGetProperty("maxLength", out var maxLen) && maxLen.TryGetInt32(out var maxLenVal) && strVal.Length > maxLenVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' cannot exceed {maxLenVal} characters."));
                    }
                    if (strVal.Length > 0 && schema.TryGetProperty("pattern", out var pattern) && pattern.ValueKind == JsonValueKind.String)
                    {
                        try
                        {
                            if (!Regex.IsMatch(strVal, pattern.GetString()!, RegexOptions.None, TimeSpan.FromMilliseconds(100)))
                                errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' is not in the expected format."));
                        }
                        catch (Exception ex) when (ex is ArgumentException or RegexMatchTimeoutException)
                        {
                            // A broken or pathological pattern is a form-definition bug, not the submitter's.
                        }
                    }
                    if (strVal.Length > 0 && schema.TryGetProperty("format", out var format) &&
                        format.ValueKind == JsonValueKind.String && format.GetString() == "email" &&
                        !Regex.IsMatch(strVal, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be a valid email address."));
                    }
                    break;

                case "number":
                    if (value.ValueKind != JsonValueKind.Number)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be a number."));
                        return;
                    }
                    if (schema.TryGetProperty("minimum", out var minNum) && minNum.TryGetDecimal(out var minNumVal) && value.GetDecimal() < minNumVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be at least {minNumVal}."));
                    }
                    if (schema.TryGetProperty("maximum", out var maxNum) && maxNum.TryGetDecimal(out var maxNumVal) && value.GetDecimal() > maxNumVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' cannot exceed {maxNumVal}."));
                    }
                    break;

                case "integer":
                    if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt64(out var intVal))
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be an integer."));
                        return;
                    }
                    if (schema.TryGetProperty("minimum", out var minInt) && minInt.TryGetInt64(out var minIntVal) && intVal < minIntVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be at least {minIntVal}."));
                    }
                    if (schema.TryGetProperty("maximum", out var maxInt) && maxInt.TryGetInt64(out var maxIntVal) && intVal > maxIntVal)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' cannot exceed {maxIntVal}."));
                    }
                    break;

                case "boolean":
                    if (value.ValueKind != JsonValueKind.True && value.ValueKind != JsonValueKind.False)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be a boolean."));
                    }
                    break;

                case "array":
                    if (value.ValueKind != JsonValueKind.Array)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be an array."));
                    }
                    break;

                case "object":
                    if (value.ValueKind != JsonValueKind.Object)
                    {
                        errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' must be an object."));
                    }
                    break;
            }
        }

        // Check enum
        if (schema.TryGetProperty("enum", out var enumProp) && enumProp.ValueKind == JsonValueKind.Array)
        {
            var matched = false;
            var valStr = value.ValueKind == JsonValueKind.String ? value.GetString() : value.GetRawText();

            foreach (var enumOption in enumProp.EnumerateArray())
            {
                var optionStr = enumOption.ValueKind == JsonValueKind.String ? enumOption.GetString() : enumOption.GetRawText();
                if (string.Equals(valStr, optionStr, StringComparison.OrdinalIgnoreCase))
                {
                    matched = true;
                    break;
                }
            }

            if (!matched)
            {
                errors.Add(new DynamicFormValidationError(fieldName, $"Value for '{fieldName}' is not in the allowed list of options."));
            }
        }
    }

    private static void ValidateCustomRules(
        string fieldName,
        JsonElement value,
        JsonElement ruleSchema,
        List<DynamicFormValidationError> errors)
    {
        if (ruleSchema.ValueKind == JsonValueKind.Object)
        {
            if (ruleSchema.TryGetProperty("required", out var req) && req.GetBoolean())
            {
                if (value.ValueKind == JsonValueKind.Null ||
                    value.ValueKind == JsonValueKind.Undefined ||
                    (value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString())))
                {
                    errors.Add(new DynamicFormValidationError(fieldName, $"Field '{fieldName}' is required by validation rules."));
                }
            }
        }
    }
}
