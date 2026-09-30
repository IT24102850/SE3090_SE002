namespace SmeBackend.Middleware;

/// <summary>
/// Which browser origins may call the API (Program.cs, "AllowFrontend").
///
/// Allowed: the configured origins (the deployed web app by default), that
/// project's Vercel preview deployments, and any port on localhost /
/// 127.0.0.1 for the Vite dev server and `flutter run -d chrome`, whose port
/// changes every run. Everything else is refused.
/// </summary>
public static class CorsOrigins
{
    private const string VercelPreviewPrefix = "se-3090-se-002-";

    public static bool IsAllowed(string origin, IReadOnlyCollection<string> configured)
    {
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
            return false;

        if (configured.Any(o => string.Equals(o.TrimEnd('/'), origin.TrimEnd('/'), StringComparison.OrdinalIgnoreCase)))
            return true;

        if (uri.Host is "localhost" or "127.0.0.1")
            return uri.Scheme is "http" or "https";

        return uri.Scheme == "https"
            && uri.Host.EndsWith(".vercel.app", StringComparison.OrdinalIgnoreCase)
            && uri.Host.StartsWith(VercelPreviewPrefix, StringComparison.OrdinalIgnoreCase);
    }
}
