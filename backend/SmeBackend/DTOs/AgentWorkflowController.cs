using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Shared;
using System;
using System.Threading.Tasks;

namespace SmeBackend.Controllers
{
    [ApiController]
    [Route("api/agent")]
    [Authorize]
    public class AgentWorkflowController : ControllerBase
    {
        // Any authenticated user can view workflows
        [HttpGet("workflows")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager},{Roles.Staff}")]
        public async Task<IActionResult> GetWorkflows([FromQuery] Guid tenantId)
        {
            return Ok();
        }

        // Only Admin/Manager can approve/reject high-impact actions
        [HttpPost("workflow/{id}/approve")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
        public async Task<IActionResult> ApproveWorkflow(Guid id)
        {
            return Ok();
        }

        [HttpPost("workflow/{id}/reject")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
        public async Task<IActionResult> RejectWorkflow(Guid id, [FromBody] RejectDto dto)
        {
            return Ok();
        }

        [HttpPost("workflow/{id}/revise")]
        [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
        public async Task<IActionResult> ReviseWorkflow(Guid id, [FromBody] ReviseDto dto)
        {
            return Ok();
        }
    }
}