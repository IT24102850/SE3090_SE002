using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AllowBranchScopedInventorySkus : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_InventoryItems_TenantId_Sku",
                table: "InventoryItems");

            migrationBuilder.CreateIndex(
                name: "IX_InventoryItems_TenantId_BranchId_Sku",
                table: "InventoryItems",
                columns: new[] { "TenantId", "BranchId", "Sku" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_InventoryItems_TenantId_BranchId_Sku",
                table: "InventoryItems");

            migrationBuilder.CreateIndex(
                name: "IX_InventoryItems_TenantId_Sku",
                table: "InventoryItems",
                columns: new[] { "TenantId", "Sku" },
                unique: true);
        }
    }
}
