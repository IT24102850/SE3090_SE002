using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

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
