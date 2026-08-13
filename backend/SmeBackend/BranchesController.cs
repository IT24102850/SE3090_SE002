using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;

namespace SmeBackend.Controllers;

// Minimal read model for the Booking Engine's Multi-Branch Schedule view.
// Full branch management (create/edit/deactivate) belongs to the shared
// multi-tenancy foundation, not the booking engine.
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
}
