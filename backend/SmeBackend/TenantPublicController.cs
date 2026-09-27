using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;

namespace SmeBackend.Controllers
{
    [ApiController]
    [Route("api/tenant/public")]
    public class TenantPublicController : ControllerBase
    {
        private readonly AppDbContext _db;
        public TenantPublicController(AppDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetPublicTenants()
        {
            var tenants = await _db.Tenants
                .Where(t => t.IsActive)
                // The "Unify Platform" tenant only exists to host the
                // owner's account (Data/PlatformOwnerSeeder.cs); it is not
                // a business anyone can book.
                .Where(t => t.BusinessType != SmeBackend.Data.PlatformOwnerSeeder.PlatformBusinessType
                            && t.BusinessType != SmeBackend.Services.CustomerAccountService.PoolBusinessType)
                .Select(t => new
                {
                    t.Id,
                    t.Name,
                    BusinessType = t.BusinessType,
                    t.SubType,
                    t.LogoUrl
                })
                .ToListAsync();
            return Ok(tenants);
        }
    }
}