using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BookingTypesController : ControllerBase
{
    private readonly AppDbContext _db;
    public BookingTypesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid tenantId, [FromQuery] string? status)
    {
        var query = _db.BookingTypes.AsNoTracking().Where(bt => bt.TenantId == tenantId);
        if (!string.IsNullOrEmpty(status) && Enum.TryParse<BookingTypeStatus>(status, true, out var s))
            query = query.Where(bt => bt.Status == s);

        var items = await query
            .OrderBy(bt => bt.Name)
            .Select(bt => new
            {
                bt.Id,
                bt.Name,
                bt.Slug,
                bt.Description,
                bt.ColorHex,
                Status = bt.Status.ToString(),
                bt.DefaultDurationMinutes,
                bt.RequiresApproval,
                bt.MaxParticipants,
                bt.BufferMinutesBefore,
                bt.BufferMinutesAfter,
                bt.BookingUnit,
                bt.ConfigJson
            })
            .ToListAsync();

        return Ok(items);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var bt = await _db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (bt == null) return NotFound();
        return Ok(bt);
    }

    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Create([FromBody] CreateBookingTypeDto dto)
    {
        var slug = Slugify(dto.Name);
        if (await _db.BookingTypes.AnyAsync(bt => bt.Slug == slug))
            slug = $"{slug}-{Guid.NewGuid().ToString()[..6]}";

        var bookingType = new BookingType
        {
            TenantId = dto.TenantId,
            Name = dto.Name,
            Slug = slug,
            Description = dto.Description,
            ColorHex = string.IsNullOrEmpty(dto.ColorHex) ? "#3B82F6" : dto.ColorHex,
            DefaultDurationMinutes = dto.DefaultDurationMinutes ?? 60,
            RequiresApproval = dto.RequiresApproval ?? false,
            MaxParticipants = dto.MaxParticipants,
            BufferMinutesBefore = dto.BufferMinutesBefore ?? 0,
            BufferMinutesAfter = dto.BufferMinutesAfter ?? 0,
            BookingUnit = string.IsNullOrEmpty(dto.BookingUnit) ? "Slot" : dto.BookingUnit,
            ConfigJson = dto.ConfigJson,
            Status = BookingTypeStatus.Active
        };

        _db.BookingTypes.Add(bookingType);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = bookingType.Id }, bookingType);
    }

    [HttpPut("{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateBookingTypeDto dto)
    {
        var bt = await _db.BookingTypes.FindAsync(id);
        if (bt == null) return NotFound();

        if (!string.IsNullOrEmpty(dto.Name)) bt.Name = dto.Name;
        if (dto.Description != null) bt.Description = dto.Description;
        if (!string.IsNullOrEmpty(dto.ColorHex)) bt.ColorHex = dto.ColorHex;
        if (dto.Status.HasValue) bt.Status = dto.Status.Value;
        if (dto.DefaultDurationMinutes.HasValue) bt.DefaultDurationMinutes = dto.DefaultDurationMinutes.Value;
        if (dto.RequiresApproval.HasValue) bt.RequiresApproval = dto.RequiresApproval.Value;
        if (dto.MaxParticipants.HasValue) bt.MaxParticipants = dto.MaxParticipants;
        if (dto.BufferMinutesBefore.HasValue) bt.BufferMinutesBefore = dto.BufferMinutesBefore.Value;
        if (dto.BufferMinutesAfter.HasValue) bt.BufferMinutesAfter = dto.BufferMinutesAfter.Value;
        if (!string.IsNullOrEmpty(dto.BookingUnit)) bt.BookingUnit = dto.BookingUnit;
        if (dto.ConfigJson != null) bt.ConfigJson = dto.ConfigJson;
        bt.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(bt);
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var bt = await _db.BookingTypes.FindAsync(id);
        if (bt == null) return NotFound();

        bt.DeletedAt = DateTime.UtcNow;
        bt.Status = BookingTypeStatus.Archived;
        bt.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static string Slugify(string name) =>
        new string(name.ToLowerInvariant().Trim().Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray())
            .Replace("--", "-").Trim('-');
}

public record CreateBookingTypeDto(
    Guid TenantId,
    string Name,
    string? Description,
    string? ColorHex,
    int? DefaultDurationMinutes,
    bool? RequiresApproval,
    int? MaxParticipants,
    int? BufferMinutesBefore,
    int? BufferMinutesAfter,
    string? BookingUnit,
    string? ConfigJson
);

public record UpdateBookingTypeDto(
    string? Name,
    string? Description,
    string? ColorHex,
    BookingTypeStatus? Status,
    int? DefaultDurationMinutes,
    bool? RequiresApproval,
    int? MaxParticipants,
    int? BufferMinutesBefore,
    int? BufferMinutesAfter,
    string? BookingUnit,
    string? ConfigJson
);
