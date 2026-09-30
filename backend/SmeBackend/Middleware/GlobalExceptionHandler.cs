using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace SmeBackend.Middleware;

/// <summary>
/// The one place an unhandled exception is turned into a response.
///
/// Controllers handle the failures they expect (validation, conflicts, not
/// found) themselves; this catches everything else so a client always gets an
/// RFC 7807 ProblemDetails body with a trace id - never a stack trace, and
/// never a bare 500 with an empty body. The exception itself is logged with
/// the same trace id, so a user's error report can be matched to the log.
/// </summary>
public sealed class GlobalExceptionHandler(
    IProblemDetailsService problemDetailsService,
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var (status, title) = Map(exception);

        if (status >= StatusCodes.Status500InternalServerError)
            logger.LogError(exception, "Unhandled exception on {Method} {Path} (trace {TraceId})",
                httpContext.Request.Method, httpContext.Request.Path, httpContext.TraceIdentifier);
        else
            logger.LogWarning("{ExceptionType} on {Method} {Path} (trace {TraceId}): {Message}",
                exception.GetType().Name, httpContext.Request.Method, httpContext.Request.Path,
                httpContext.TraceIdentifier, exception.Message);

        httpContext.Response.StatusCode = status;
        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = new ProblemDetails
            {
                Status = status,
                Title = title,
                // Internal messages can name tables, columns or hosts; only
                // client errors echo theirs back.
                Detail = status < 500 ? exception.Message : "An unexpected error occurred. Quote the trace id when reporting it.",
                Instance = httpContext.Request.Path,
            },
        });
    }

    internal static (int Status, string Title) Map(Exception exception) => exception switch
    {
        OperationCanceledException => (499, "Request cancelled"),
        UnauthorizedAccessException => (StatusCodes.Status403Forbidden, "Forbidden"),
        KeyNotFoundException => (StatusCodes.Status404NotFound, "Not found"),
        ArgumentException or FormatException => (StatusCodes.Status400BadRequest, "Invalid request"),
        DbUpdateConcurrencyException => (StatusCodes.Status409Conflict, "The record was changed by someone else"),
        DbUpdateException => (StatusCodes.Status409Conflict, "The change violates a data constraint"),
        _ => (StatusCodes.Status500InternalServerError, "Internal server error"),
    };
}
