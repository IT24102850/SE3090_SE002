using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class ScopeResourceCodeToTenant : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_resources_Code",
                table: "resources");

            migrationBuilder.CreateIndex(
                name: "IX_resources_TenantId_Code",
                table: "resources",
                columns: new[] { "TenantId", "Code" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_resources_TenantId_Code",
                table: "resources");

            migrationBuilder.CreateIndex(
                name: "IX_resources_Code",
                table: "resources",
                column: "Code",
                unique: true);
        }
    }
}
