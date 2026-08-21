namespace SmeBackend.Shared;

// Npgsql requires DateTime.Kind == Utc when comparing against "timestamp with time
// zone" columns. Model-bound DateTimes (query string, and JSON bodies without a
// trailing 'Z'/offset) come back as Kind=Unspecified, so every DateTime that
// reaches EF Core must be normalized through here first.
public static class DateTimeUtil
{
    public static DateTime AsUtc(DateTime dt) =>
        dt.Kind == DateTimeKind.Utc ? dt : DateTime.SpecifyKind(dt, DateTimeKind.Utc);

    public static DateTime? AsUtc(DateTime? dt) => dt.HasValue ? AsUtc(dt.Value) : null;
}
