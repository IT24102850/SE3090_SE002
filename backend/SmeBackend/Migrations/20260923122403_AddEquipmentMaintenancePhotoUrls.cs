using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddEquipmentMaintenancePhotoUrls : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PhotoUrls",
                table: "equipment_maintenances",
                type: "jsonb",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PhotoUrls",
                table: "equipment_maintenances");
        }
    }
}
