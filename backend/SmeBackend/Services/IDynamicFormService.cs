using System.Text.Json;
using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services;

public interface IDynamicFormService
{
    Task<(bool Found, DynamicFormValidationResponse Response)> ValidateFormAsync(
        Guid tenantId,
        string formType,
        JsonElement data,
        CancellationToken cancellationToken = default);

    Task<(bool Found, bool IsValid, string? Error, IReadOnlyList<DynamicFormValidationError>? ValidationErrors, FormSubmissionResponse? Submission)> SubmitFormAsync(
        Guid tenantId,
        string formType,
        DynamicFormSubmitRequest request,
        CancellationToken cancellationToken = default);

    // Form builder
    Task<IReadOnlyList<DynamicFormResponse>> GetFormsAsync(Guid tenantId, CancellationToken ct = default);
    Task<BillingResult<DynamicFormResponse>> GetFormAsync(Guid tenantId, string formType, CancellationToken ct = default);
    Task<BillingResult<DynamicFormResponse>> UpsertFormAsync(Guid tenantId, string formType, UpsertDynamicFormRequest request, CancellationToken ct = default);
    Task<BillingResult<bool>> DeleteFormAsync(Guid tenantId, string formType, CancellationToken ct = default);
    Task<BillingResult<IReadOnlyList<FormSubmissionResponse>>> GetSubmissionsAsync(Guid tenantId, string formType, Guid? entityId, int take, CancellationToken ct = default);
}
