using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddSupplierLeadTimeDays : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "LeadTimeDays",
                table: "Suppliers",
                type: "integer",
                nullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_Suppliers_LeadTimeDays",
                table: "Suppliers",
                sql: "\"LeadTimeDays\" IS NULL OR \"LeadTimeDays\" BETWEEN 1 AND 90");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_Suppliers_LeadTimeDays",
                table: "Suppliers");

            migrationBuilder.DropColumn(
                name: "LeadTimeDays",
                table: "Suppliers");
        }
    }
}
