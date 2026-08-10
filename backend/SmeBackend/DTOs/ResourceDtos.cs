using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

public class CreateResourceDto
{
    [Required]
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? ResourceType { get; set; }
    [Required]
    public Guid BranchId { get; set; }
}

public class ScheduleDto
{
    [Required]
    public List<AvailabilitySlotDto> Availability { get; set; } = [];
}

public class AvailabilitySlotDto
{
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
}
