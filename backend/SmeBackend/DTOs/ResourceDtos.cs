using System.ComponentModel.DataAnnotations;
using SmeBackend.Models;

namespace SmeBackend.DTOs;

public record CreateResourceDto(
    [Required] Guid TenantId,
    Guid? BranchId,
    [Required][MaxLength(100)] string Name,
    [MaxLength(20)] string? Code,
    ResourceCategory Category,
    [MaxLength(500)] string? Description,
    int? Capacity,
    decimal? HourlyRate,
    [MaxLength(100)] string? Specialty,
    Guid? LinkedUserId,
    // Free-form JSON bag for business-type-specific ranking signals (rating,
    // cuisine, distance, wait time, ...) consumed by the Domain Analysis
    // Agent — see agentic-ai-service/agents/domain_analysis_agent.py.
    string? CustomAttributes,
    string? LocationMetadata
);

public record UpdateResourceDto(
    [MaxLength(100)] string? Name,
    Guid? BranchId,
    ResourceCategory? Category,
    ResourceStatus? Status,
    [MaxLength(500)] string? Description,
    int? Capacity,
    decimal? HourlyRate,
    [MaxLength(100)] string? Specialty,
    Guid? LinkedUserId,
    string? CustomAttributes,
    string? LocationMetadata
);

public record DaySchedule(
    int DayOfWeek,
    TimeSpan StartTime,
    TimeSpan EndTime,
    bool IsAvailable,
    TimeSpan? LunchBreakStart = null,
    TimeSpan? LunchBreakEnd = null,
    decimal? MaxDailyBookedHours = null
);

public record SetScheduleDto(List<DaySchedule> Days);
