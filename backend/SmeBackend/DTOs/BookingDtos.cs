using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

public class CreateBookingDto
{
    [Required]
    public Guid CustomerId { get; set; }

    [Required]
    public Guid BranchId { get; set; }

    [Required]
    public Guid ResourceId { get; set; }

    [Required]
    public DateTime StartTime { get; set; }

    public string? Notes { get; set; }
}

public class UpdateBookingDto
{
    public Guid? BranchId { get; set; }
    public Guid? ResourceId { get; set; }
    public DateTime? StartTime { get; set; }
    public string? Notes { get; set; }
    public string? Status { get; set; }
}

public class BulkScheduleDto
{
    [Required]
    public Guid BranchId { get; set; }

    [Required]
    public Guid ResourceId { get; set; }

    [Required]
    public DateTime StartDate { get; set; }

    [Required]
    public DateTime EndDate { get; set; }

    public string? Notes { get; set; }
}