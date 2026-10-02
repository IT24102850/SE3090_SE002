using SmeBackend.Services;

namespace SmeBackend.Tests;

/// Stand-ins for the two dependencies AuthController grew when password
/// recovery and mobile social sign-in arrived.
///
/// The suites that construct AuthController here exercise sign-in, profile
/// and password *change* - none of them touch a reset code or a provider
/// token. Real implementations would pull in SMTP and an HTTP client for no
/// benefit, so these fail closed instead: any test that does reach these
/// paths gets a clear "not configured" rather than a quiet pass.
internal sealed class StubPasswordResetManager : IPasswordResetManager
{
    public Task<bool> GenerateResetCodeAsync(string email) => Task.FromResult(false);

    public bool VerifyCode(string email, string code) => false;

    public bool VerifyAndConsumeCode(string email, string code) => false;
}

internal sealed class StubMobileExternalAuthService : IMobileExternalAuthService
{
    public Task<ExternalIdentity> GetVerifiedIdentityAsync(
        string provider, string? idToken, string? accessToken, CancellationToken cancellationToken) =>
        throw new InvalidOperationException(
            "External sign-in is not configured in tests; give the test a real service if it needs one.");
}
