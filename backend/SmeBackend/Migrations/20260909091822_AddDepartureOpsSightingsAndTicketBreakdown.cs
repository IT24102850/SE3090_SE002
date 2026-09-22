using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddDepartureOpsSightingsAndTicketBreakdown : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiryDate",
                table: "EquipmentItems",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "DepartureId",
                table: "bookings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Source",
                table: "bookings",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TicketBreakdown",
                table: "bookings",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Waiver",
                table: "bookings",
                type: "jsonb",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "departures",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: false),
                    BookingTypeId = table.Column<Guid>(type: "uuid", nullable: true),
                    ScheduledDeparture = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ScheduledReturn = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ActualDepartureAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ActualReturnAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    CaptainUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Crew = table.Column<string>(type: "jsonb", nullable: true),
                    SafetyChecklist = table.Column<string>(type: "jsonb", nullable: true),
                    LicensedCapacity = table.Column<int>(type: "integer", nullable: true),
                    CancellationReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    UpdatedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_departures", x => x.Id);
                    table.ForeignKey(
                        name: "FK_departures_booking_types_BookingTypeId",
                        column: x => x.BookingTypeId,
                        principalTable: "booking_types",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_departures_resources_ResourceId",
                        column: x => x.ResourceId,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "weather_observations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: true),
                    DepartureId = table.Column<Guid>(type: "uuid", nullable: true),
                    ObservedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    WindSpeedKnots = table.Column<decimal>(type: "numeric(6,2)", nullable: true),
                    WaveHeightMetres = table.Column<decimal>(type: "numeric(6,2)", nullable: true),
                    VisibilityKm = table.Column<decimal>(type: "numeric(6,2)", nullable: true),
                    SeaStateCode = table.Column<int>(type: "integer", nullable: true),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Source = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    RecordedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_weather_observations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "sightings_logs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: false),
                    DepartureId = table.Column<Guid>(type: "uuid", nullable: true),
                    BookingId = table.Column<Guid>(type: "uuid", nullable: true),
                    DepartureDateTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Species = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Count = table.Column<int>(type: "integer", nullable: true),
                    LocationLat = table.Column<double>(type: "double precision", nullable: true),
                    LocationLng = table.Column<double>(type: "double precision", nullable: true),
                    Behaviour = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    PhotoUrls = table.Column<string>(type: "jsonb", nullable: true),
                    LoggedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sightings_logs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_sightings_logs_departures_DepartureId",
                        column: x => x.DepartureId,
                        principalTable: "departures",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_sightings_logs_resources_ResourceId",
                        column: x => x.ResourceId,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_bookings_DepartureId",
                table: "bookings",
                column: "DepartureId");

            migrationBuilder.CreateIndex(
                name: "IX_departures_BookingTypeId",
                table: "departures",
                column: "BookingTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_departures_ResourceId_ScheduledDeparture",
                table: "departures",
                columns: new[] { "ResourceId", "ScheduledDeparture" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_departures_TenantId_ScheduledDeparture",
                table: "departures",
                columns: new[] { "TenantId", "ScheduledDeparture" });

            migrationBuilder.CreateIndex(
                name: "IX_departures_TenantId_Status",
                table: "departures",
                columns: new[] { "TenantId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_sightings_logs_DepartureId",
                table: "sightings_logs",
                column: "DepartureId");

            migrationBuilder.CreateIndex(
                name: "IX_sightings_logs_ResourceId",
                table: "sightings_logs",
                column: "ResourceId");

            migrationBuilder.CreateIndex(
                name: "IX_sightings_logs_TenantId_DepartureDateTime",
                table: "sightings_logs",
                columns: new[] { "TenantId", "DepartureDateTime" });

            migrationBuilder.CreateIndex(
                name: "IX_sightings_logs_TenantId_Species",
                table: "sightings_logs",
                columns: new[] { "TenantId", "Species" });

            migrationBuilder.CreateIndex(
                name: "IX_weather_observations_DepartureId",
                table: "weather_observations",
                column: "DepartureId");

            migrationBuilder.CreateIndex(
                name: "IX_weather_observations_TenantId_ObservedAt",
                table: "weather_observations",
                columns: new[] { "TenantId", "ObservedAt" });

            migrationBuilder.AddForeignKey(
                name: "FK_bookings_departures_DepartureId",
                table: "bookings",
                column: "DepartureId",
                principalTable: "departures",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_bookings_departures_DepartureId",
                table: "bookings");

            migrationBuilder.DropTable(
                name: "sightings_logs");

            migrationBuilder.DropTable(
                name: "weather_observations");

            migrationBuilder.DropTable(
                name: "departures");

            migrationBuilder.DropIndex(
                name: "IX_bookings_DepartureId",
                table: "bookings");

            migrationBuilder.DropColumn(
                name: "ExpiryDate",
                table: "EquipmentItems");

            migrationBuilder.DropColumn(
                name: "DepartureId",
                table: "bookings");

            migrationBuilder.DropColumn(
                name: "Source",
                table: "bookings");

            migrationBuilder.DropColumn(
                name: "TicketBreakdown",
                table: "bookings");

            migrationBuilder.DropColumn(
                name: "Waiver",
                table: "bookings");
        }
    }
}
