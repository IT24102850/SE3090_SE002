using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

public class CreateBookingDto
{
    [Required]
    public Guid BranchId { get; set; }
    
    [Required]
    public string BookingType { get; set; } = string.Empty;
    
    [Required]
    public Guid CustomerId { get; set; }
    
    [Required]
    public DateTime ScheduledDateTime { get; set; }
    
    [Required]
    public int Duration { get; set; }
    
    public string? Notes { get; set; }
}