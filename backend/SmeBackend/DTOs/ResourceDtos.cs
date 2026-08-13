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
    Guid? LinkedUserId
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
    Guid? LinkedUserId
);

public record DaySchedule(int DayOfWeek, TimeSpan StartTime, TimeSpan EndTime, bool IsAvailable);

public record SetScheduleDto(List<DaySchedule> Days);
