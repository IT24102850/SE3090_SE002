using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/dynamic-forms")]
[Authorize]
[Produces("application/json")]
public class DynamicFormsController : BillingControllerBase
{
    private readonly IDynamicFormService _dynamicFormService;

    public DynamicFormsController(IDynamicFormService dynamicFormService)
    {
        _dynamicFormService = dynamicFormService;
    }

    /// <summary>Lists the business's form definitions.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<DynamicFormResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<DynamicFormResponse>>> GetForms(CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _dynamicFormService.GetFormsAsync(actor.TenantId, ct));
    }

    /// <summary>Gets one form definition (for rendering it).</summary>
    [HttpGet("{formType}")]
    [ProducesResponseType(typeof(DynamicFormResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<DynamicFormResponse>> GetForm(string formType, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _dynamicFormService.GetFormAsync(actor.TenantId, formType, ct));
    }

    /// <summary>Creates or replaces a form definition (the Dynamic Form Builder's save).</summary>
    [HttpPut("{formType}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(DynamicFormResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(DynamicFormResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<DynamicFormResponse>> UpsertForm(string formType, [FromBody] UpsertDynamicFormRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _dynamicFormService.UpsertFormAsync(actor.TenantId, formType, request, ct));
    }

    [HttpDelete("{formType}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DeleteForm(string formType, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _dynamicFormService.DeleteFormAsync(actor.TenantId, formType, ct);
        return result.Success ? NoContent() : FromResult(result);
    }

    [HttpGet("{formType}/submissions")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(IReadOnlyList<FormSubmissionResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<FormSubmissionResponse>>> GetSubmissions(
        string formType, [FromQuery] Guid? entityId = null, [FromQuery] int take = 50, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _dynamicFormService.GetSubmissionsAsync(actor.TenantId, formType, entityId, take, ct));
    }

    /// <summary>
    /// Validates submitted JSON data against the dynamic form's stored JSON schema and validation rules.
    /// </summary>
    [HttpPost("{formType}/validate")]
    [ProducesResponseType(typeof(DynamicFormValidationResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(DynamicFormValidationResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ValidateForm(string formType, [FromBody] JsonElement data, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();

        var (found, response) = await _dynamicFormService.ValidateFormAsync(actor.TenantId, formType, data, ct);
        if (!found) return NotFound(new { message = $"Dynamic form '{formType}' not found for the current tenant." });
        return response.IsValid ? Ok(response) : BadRequest(response);
    }

    /// <summary>
    /// Validates and records a submission for a dynamic form.
    /// </summary>
    [HttpPost("{formType}/submit")]
    [ProducesResponseType(typeof(FormSubmissionResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<FormSubmissionResponse>> SubmitForm(string formType, [FromBody] DynamicFormSubmitRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var (found, isValid, error, validationErrors, submission) =
            await _dynamicFormService.SubmitFormAsync(actor.TenantId, formType, request, ct);

        if (!found) return NotFound(new { message = $"Dynamic form '{formType}' not found for the current tenant." });
        if (!isValid) return BadRequest(new { message = error ?? "Form validation failed.", errors = validationErrors });
        return StatusCode(StatusCodes.Status201Created, submission);
    }
}
