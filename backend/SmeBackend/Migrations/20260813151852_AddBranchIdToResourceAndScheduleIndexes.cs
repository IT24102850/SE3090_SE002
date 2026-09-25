using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddBranchIdToResourceAndScheduleIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "BranchId",
                table: "resources",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "agent_workflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Objective = table.Column<string>(type: "text", nullable: false),
                    PlanJson = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    CurrentStep = table.Column<int>(type: "integer", nullable: false),
                    ToolResultsJson = table.Column<string>(type: "text", nullable: true),
                    ValidationResults = table.Column<string>(type: "text", nullable: true),
                    ApprovalStatus = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    ApprovedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    ApprovedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    FinalOutcome = table.Column<string>(type: "text", nullable: true),
                    ErrorLog = table.Column<string>(type: "text", nullable: true),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_agent_workflows", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "availability_slots",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: true),
                    Date = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    StartTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    EndTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    IsBooked = table.Column<bool>(type: "boolean", nullable: false),
                    BookingId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_availability_slots", x => x.Id);
                    table.ForeignKey(
                        name: "FK_availability_slots_resources_ResourceId",
                        column: x => x.ResourceId,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "booking_reminders",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BookingId = table.Column<Guid>(type: "uuid", nullable: true),
                    Channel = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    SentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_booking_reminders", x => x.Id);
                    table.ForeignKey(
                        name: "FK_booking_reminders_bookings_BookingId",
                        column: x => x.BookingId,
                        principalTable: "bookings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "recurring_patterns",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BookingId = table.Column<Guid>(type: "uuid", nullable: true),
                    Frequency = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    EndDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    DaysOfWeek = table.Column<List<int>>(type: "integer[]", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recurring_patterns", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recurring_patterns_bookings_BookingId",
                        column: x => x.BookingId,
                        principalTable: "bookings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "resource_schedules",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: true),
                    DayOfWeek = table.Column<int>(type: "integer", nullable: false),
                    StartTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    EndTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    IsAvailable = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_resource_schedules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_resource_schedules_resources_ResourceId",
                        column: x => x.ResourceId,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_resources_BranchId",
                table: "resources",
                column: "BranchId");

            migrationBuilder.CreateIndex(
                name: "IX_resources_TenantId_BranchId",
                table: "resources",
                columns: new[] { "TenantId", "BranchId" });

            migrationBuilder.CreateIndex(
                name: "IX_agent_workflows_CreatedAt",
                table: "agent_workflows",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_agent_workflows_TenantId_Status",
                table: "agent_workflows",
                columns: new[] { "TenantId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_availability_slots_BookingId",
                table: "availability_slots",
                column: "BookingId");

            migrationBuilder.CreateIndex(
                name: "IX_availability_slots_ResourceId_Date",
                table: "availability_slots",
                columns: new[] { "ResourceId", "Date" });

            migrationBuilder.CreateIndex(
                name: "IX_availability_slots_ResourceId_Date_StartTime_EndTime",
                table: "availability_slots",
                columns: new[] { "ResourceId", "Date", "StartTime", "EndTime" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_booking_reminders_BookingId",
                table: "booking_reminders",
                column: "BookingId");

            migrationBuilder.CreateIndex(
                name: "IX_booking_reminders_Status",
                table: "booking_reminders",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_recurring_patterns_BookingId",
                table: "recurring_patterns",
                column: "BookingId");

            migrationBuilder.CreateIndex(
                name: "IX_resource_schedules_ResourceId_DayOfWeek",
                table: "resource_schedules",
                columns: new[] { "ResourceId", "DayOfWeek" });

            migrationBuilder.AddForeignKey(
                name: "FK_resources_Branches_BranchId",
                table: "resources",
                column: "BranchId",
                principalTable: "Branches",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_resources_Branches_BranchId",
                table: "resources");

            migrationBuilder.DropTable(
                name: "agent_workflows");

            migrationBuilder.DropTable(
                name: "availability_slots");

            migrationBuilder.DropTable(
                name: "booking_reminders");

            migrationBuilder.DropTable(
                name: "recurring_patterns");

            migrationBuilder.DropTable(
                name: "resource_schedules");

            migrationBuilder.DropIndex(
                name: "IX_resources_BranchId",
                table: "resources");

            migrationBuilder.DropIndex(
                name: "IX_resources_TenantId_BranchId",
                table: "resources");

            migrationBuilder.DropColumn(
                name: "BranchId",
                table: "resources");
        }
    }
}
