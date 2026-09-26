using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class CompleteBillingEngine : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PayerLabel",
                table: "payments",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Provider",
                table: "payments",
                type: "character varying(30)",
                maxLength: 30,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "payments",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Succeeded");

            migrationBuilder.AddColumn<string>(
                name: "ApiKeyEncrypted",
                table: "payment_gateways",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsTestMode",
                table: "payment_gateways",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<string>(
                name: "PublicKey",
                table: "payment_gateways",
                type: "character varying(300)",
                maxLength: 300,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WebhookSecretEncrypted",
                table: "payment_gateways",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WebhookUrl",
                table: "payment_gateways",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "BranchId",
                table: "invoices",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DiscountCode",
                table: "invoices",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastReminderAt",
                table: "invoices",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Notes",
                table: "invoices",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ScheduleGroup",
                table: "invoices",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ScheduleLabel",
                table: "invoices",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "SubscriptionId",
                table: "invoices",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "TemplateId",
                table: "invoices",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DocumentsJson",
                table: "insurance_claims",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Notes",
                table: "insurance_claims",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ReviewStartedAt",
                table: "insurance_claims",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "MaxAmount",
                table: "commission_rules",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "MinAmount",
                table: "commission_rules",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Role",
                table: "commission_rules",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "invoice_templates",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    IsDefault = table.Column<bool>(type: "boolean", nullable: false),
                    LayoutJson = table.Column<string>(type: "jsonb", nullable: false),
                    AccentColor = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    HeaderText = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    FooterText = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_invoice_templates", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_invoices_ScheduleGroup",
                table: "invoices",
                column: "ScheduleGroup");

            migrationBuilder.CreateIndex(
                name: "IX_invoices_SubscriptionId",
                table: "invoices",
                column: "SubscriptionId");

            migrationBuilder.CreateIndex(
                name: "IX_invoices_TenantId_DueDate",
                table: "invoices",
                columns: new[] { "TenantId", "DueDate" });

            migrationBuilder.CreateIndex(
                name: "IX_invoice_templates_TenantId_Name",
                table: "invoice_templates",
                columns: new[] { "TenantId", "Name" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "invoice_templates");

            migrationBuilder.DropIndex(
                name: "IX_invoices_ScheduleGroup",
                table: "invoices");

            migrationBuilder.DropIndex(
                name: "IX_invoices_SubscriptionId",
                table: "invoices");

            migrationBuilder.DropIndex(
                name: "IX_invoices_TenantId_DueDate",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "PayerLabel",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "Provider",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "ApiKeyEncrypted",
                table: "payment_gateways");

            migrationBuilder.DropColumn(
                name: "IsTestMode",
                table: "payment_gateways");

            migrationBuilder.DropColumn(
                name: "PublicKey",
                table: "payment_gateways");

            migrationBuilder.DropColumn(
                name: "WebhookSecretEncrypted",
                table: "payment_gateways");

            migrationBuilder.DropColumn(
                name: "WebhookUrl",
                table: "payment_gateways");

            migrationBuilder.DropColumn(
                name: "BranchId",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "DiscountCode",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "LastReminderAt",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "Notes",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "ScheduleGroup",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "ScheduleLabel",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "SubscriptionId",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "TemplateId",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "DocumentsJson",
                table: "insurance_claims");

            migrationBuilder.DropColumn(
                name: "Notes",
                table: "insurance_claims");

            migrationBuilder.DropColumn(
                name: "ReviewStartedAt",
                table: "insurance_claims");

            migrationBuilder.DropColumn(
                name: "MaxAmount",
                table: "commission_rules");

            migrationBuilder.DropColumn(
                name: "MinAmount",
                table: "commission_rules");

            migrationBuilder.DropColumn(
                name: "Role",
                table: "commission_rules");
        }
    }
}
