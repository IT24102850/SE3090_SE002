using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddPaymentSettlementCurrency : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "ExchangeRate",
                table: "payments",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "SettlementAmount",
                table: "payments",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SettlementCurrency",
                table: "payments",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ExchangeRate",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "SettlementAmount",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "SettlementCurrency",
                table: "payments");
        }
    }
}
