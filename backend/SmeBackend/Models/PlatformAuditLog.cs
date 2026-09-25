namespace SmeBackend.Models;

/// Append-only trail of everything that touches the platform console:
/// sign-in attempts (failed ones included), MFA enrolment, and every
/// change the owner makes to a tenant or user. Nothing ever updates or
/// deletes a row.
public class PlatformAuditLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Guid? ActorUserId { get; set; }
    public string ActorEmail { get; set; } = string.Empty;

    /// Dotted verb, e.g. "auth.login.failed", "tenant.suspend".
    public string Action { get; set; } = string.Empty;
    public string? TargetType { get; set; }
    public Guid? TargetId { get; set; }
    public string? TargetLabel { get; set; }
    public string? Detail { get; set; }

    public bool Succeeded { get; set; } = true;
    public string IpAddress { get; set; } = string.Empty;
    public string UserAgent { get; set; } = string.Empty;
}
