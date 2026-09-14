using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

// FR-AS4: branch management. Read side stays open to any authenticated
// caller (needed by branch pickers across the app); writes are Admin-only.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BranchesController : ControllerBase
{
    private readonly AppDbContext _db;
    public BranchesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid tenantId)
    {
        var branches = await _db.Branches.AsNoTracking()
            .Where(b => b.TenantId == tenantId && b.IsActive)
            .OrderBy(b => b.Name)
            .Select(b => new { b.Id, b.Name, b.Address, b.Phone })
            .ToListAsync();

        return Ok(branches);
    }

    [HttpPost]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create([FromBody] CreateBranchDto dto)
    {
        var branch = new Branch
        {
            TenantId = dto.TenantId,
            Name = dto.Name,
            Address = dto.Address ?? string.Empty,
            Phone = dto.Phone ?? string.Empty,
            IsActive = true
        };

        _db.Branches.Add(branch);
        await _db.SaveChangesAsync();
        return Ok(branch);
    }

    [HttpPut("{id}")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateBranchDto dto)
    {
        var branch = await _db.Branches.FindAsync(id);
        if (branch == null) return NotFound();

        if (!string.IsNullOrWhiteSpace(dto.Name)) branch.Name = dto.Name;
        if (dto.Address != null) branch.Address = dto.Address;
        if (dto.Phone != null) branch.Phone = dto.Phone;
        if (dto.IsActive.HasValue) branch.IsActive = dto.IsActive.Value;
        branch.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(branch);
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(Guid id)
    {
        var branch = await _db.Branches.FindAsync(id);
        if (branch == null) return NotFound();

        branch.IsActive = false;
        branch.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}

public record CreateBranchDto(Guid TenantId, string Name, string? Address, string? Phone);
public record UpdateBranchDto(string? Name, string? Address, string? Phone, bool? IsActive);
