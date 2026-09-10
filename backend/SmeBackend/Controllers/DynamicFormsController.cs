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
public class DynamicFormsController : ControllerBase
{
    private readonly IDynamicFormService _dynamicFormService;

    public DynamicFormsController(IDynamicFormService dynamicFormService)
    {
        _dynamicFormService = dynamicFormService;
    }

    /// <summary>
    /// Validates submitted JSON data against the dynamic form's stored JSON schema and validation rules.
    /// </summary>
    [HttpPost("{formType}/validate")]
    [ProducesResponseType(typeof(DynamicFormValidationResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(DynamicFormValidationResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ValidateForm(
        [FromRoute] string formType,
        [FromBody] JsonElement data,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var (found, response) = await _dynamicFormService.ValidateFormAsync(
            tenantId,
            formType,
            data,
            cancellationToken);

        if (!found)
        {
            return NotFound(new { message = $"Dynamic form '{formType}' not found for the current tenant." });
        }

        if (!response.IsValid)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Validates and records a submission for a dynamic form.
    /// </summary>
    [HttpPost("{formType}/submit")]
    [ProducesResponseType(typeof(FormSubmissionResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<FormSubmissionResponse>> SubmitForm(
        [FromRoute] string formType,
        [FromBody] DynamicFormSubmitRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (found, isValid, error, validationErrors, submission) = await _dynamicFormService.SubmitFormAsync(
            tenantId,
            formType,
            request,
            cancellationToken);

        if (!found)
        {
            return NotFound(new { message = $"Dynamic form '{formType}' not found for the current tenant." });
        }

        if (!isValid)
        {
            return BadRequest(new
            {
                message = error ?? "Form validation failed.",
                errors = validationErrors
            });
        }

        return StatusCode(StatusCodes.Status201Created, submission);
    }

    private bool TryGetTenantId(out Guid tenantId)
    {
        var tenantClaim = User.FindFirst("tenantId")?.Value;
        return Guid.TryParse(tenantClaim, out tenantId);
    }
}
