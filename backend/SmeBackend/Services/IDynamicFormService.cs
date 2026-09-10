using System.Text.Json;
using SmeBackend.DTOs;

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
}
