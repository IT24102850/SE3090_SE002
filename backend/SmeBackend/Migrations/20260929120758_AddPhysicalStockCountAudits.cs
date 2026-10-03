using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddPhysicalStockCountAudits : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PhysicalStockCounts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    InventoryItemId = table.Column<Guid>(type: "uuid", nullable: false),
                    BranchId = table.Column<Guid>(type: "uuid", nullable: false),
                    ItemName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    Sku = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    SystemQuantityAtCount = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false),
                    CountedQuantity = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false),
                    Variance = table.Column<decimal>(type: "numeric(18,3)", precision: 18, scale: 3, nullable: false),
                    Reason = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    ReasonNotes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CountedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CountedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CountedBy = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    Reference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    PhotoUrlsJson = table.Column<string>(type: "jsonb", nullable: true),
                    ReviewedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ReviewedBy = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    ReviewedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ReviewNotes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PhysicalStockCounts", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PhysicalStockCounts_TenantId_BranchId_Status_CountedAt",
                table: "PhysicalStockCounts",
                columns: new[] { "TenantId", "BranchId", "Status", "CountedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_PhysicalStockCounts_TenantId_Reference",
                table: "PhysicalStockCounts",
                columns: new[] { "TenantId", "Reference" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PhysicalStockCounts");
        }
    }
}
