using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Shared;
using System;
using System.Threading.Tasks;

namespace SmeBackend.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class ResourcesController : ControllerBase
    {
        [HttpGet]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager},{Roles.Staff}")]
        public IActionResult GetResources([FromQuery] Guid tenantId)
        {
            return Ok();
        }

        [HttpPost]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
        public IActionResult CreateResource([FromBody] CreateResourceDto dto)
        {
            return Ok();
        }

        [HttpGet("{id}/schedule")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager},{Roles.Staff}")]
        public IActionResult GetResourceSchedule(Guid id)
        {
            return Ok();
        }

        [HttpPut("{id}/schedule")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
        public IActionResult UpdateResourceSchedule(Guid id, [FromBody] ScheduleDto dto)
        {
            return Ok();
        }
    }
}