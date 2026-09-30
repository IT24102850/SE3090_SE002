using Microsoft.EntityFrameworkCore;
using SmeBackend.Middleware;

namespace SmeBackend.Tests.Api;

public sealed class ErrorHandlingAndCorsTests
{
    [Theory]
    [InlineData(typeof(ArgumentException), 400)]
    [InlineData(typeof(FormatException), 400)]
    [InlineData(typeof(UnauthorizedAccessException), 403)]
    [InlineData(typeof(KeyNotFoundException), 404)]
    [InlineData(typeof(DbUpdateException), 409)]
    [InlineData(typeof(NullReferenceException), 500)]
    [InlineData(typeof(InvalidOperationException), 500)]
    public void GlobalExceptionHandler_MapsExceptionToStatus(Type exceptionType, int expected)
    {
        var exception = (Exception)Activator.CreateInstance(exceptionType)!;

        Assert.Equal(expected, GlobalExceptionHandler.Map(exception).Status);
    }

    [Theory]
    [InlineData("https://se-3090-se-002.vercel.app", true)]
    [InlineData("https://se-3090-se-002-git-dev-hasiru.vercel.app", true)]
    [InlineData("http://localhost:61234", true)]
    [InlineData("http://127.0.0.1:5173", true)]
    [InlineData("https://someone-else.vercel.app", false)]
    [InlineData("http://se-3090-se-002-preview.vercel.app", false)]
    [InlineData("https://evil.example.com", false)]
    [InlineData("not a url", false)]
    public void CorsOrigins_AllowsOnlyKnownOrigins(string origin, bool expected)
    {
        Assert.Equal(expected, CorsOrigins.IsAllowed(origin, new[] { "https://se-3090-se-002.vercel.app" }));
    }
}
