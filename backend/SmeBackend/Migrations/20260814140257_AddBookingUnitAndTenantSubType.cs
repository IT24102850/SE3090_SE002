using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddBookingUnitAndTenantSubType : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SubType",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BookingUnit",
                table: "booking_types",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Slot");

            migrationBuilder.AddColumn<string>(
                name: "ConfigJson",
                table: "booking_types",
                type: "jsonb",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SubType",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "BookingUnit",
                table: "booking_types");

            migrationBuilder.DropColumn(
                name: "ConfigJson",
                table: "booking_types");
        }
    }
}
