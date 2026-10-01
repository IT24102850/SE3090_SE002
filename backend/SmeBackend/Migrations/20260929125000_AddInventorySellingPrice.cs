using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using SmeBackend.Data;

#nullable disable

namespace SmeBackend.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20260929125000_AddInventorySellingPrice")]
public sealed class AddInventorySellingPrice : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "SellingPrice",
            table: "InventoryItems",
            type: "numeric(18,2)",
            precision: 18,
            scale: 2,
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "SellingPrice",
            table: "InventoryItems");
    }
}
