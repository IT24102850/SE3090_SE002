using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddPlatformCopilotWorkflows : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "platform_agent_workflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TraceId = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Objective = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    Status = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    PlanJson = table.Column<string>(type: "jsonb", nullable: true),
                    AnalysisJson = table.Column<string>(type: "jsonb", nullable: true),
                    ProposalsJson = table.Column<string>(type: "jsonb", nullable: true),
                    ValidationJson = table.Column<string>(type: "jsonb", nullable: true),
                    ObservabilityJson = table.Column<string>(type: "jsonb", nullable: true),
                    ApprovalStatus = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    DecidedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    DecidedByEmail = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    DecidedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    DecisionReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ApprovedInterventionsJson = table.Column<string>(type: "jsonb", nullable: true),
                    OutcomeJson = table.Column<string>(type: "jsonb", nullable: true),
                    ErrorLog = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ModelDriven = table.Column<bool>(type: "boolean", nullable: false),
                    EstimatedCost = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_agent_workflows", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_platform_agent_workflows_CreatedAt",
                table: "platform_agent_workflows",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_platform_agent_workflows_Status",
                table: "platform_agent_workflows",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_platform_agent_workflows_TraceId",
                table: "platform_agent_workflows",
                column: "TraceId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "platform_agent_workflows");
        }
    }
}
