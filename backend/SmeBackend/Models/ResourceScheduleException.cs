namespace SmeBackend.Models;

/// FR-AS6: one-off date overrides (holidays, closures) on top of the
/// recurring weekly ResourceSchedule. Only closures are supported — a
/// resource that's normally closed that day can't be opened via an
/// exception, keeping this additive rather than a second schedule source.
public class ResourceScheduleException : BaseEntity
{
    public Guid ResourceId { get; set; }
    public Resource? Resource { get; set; }
    public DateTime Date { get; set; }
    public string? Reason { get; set; }
}
