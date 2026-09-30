using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddDataIntegrityChecks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // NOT VALID: PostgreSQL enforces each rule on every row inserted
            // or updated from now on, but does not scan the rows already
            // there. The deployed database predates these rules, and one
            // legacy row must not be able to stop the API from starting.
            AddNotValid(migrationBuilder, "PurchaseOrderItems", "CK_purchase_order_items_quantity_positive", "\"Quantity\" > 0");
            AddNotValid(migrationBuilder, "PurchaseOrderItems", "CK_purchase_order_items_received_in_range", "\"ReceivedQuantity\" >= 0");
            AddNotValid(migrationBuilder, "PurchaseOrderItems", "CK_purchase_order_items_unit_price_non_negative", "\"UnitPrice\" >= 0");
            AddNotValid(migrationBuilder, "invoices", "CK_invoices_discount_non_negative", "\"Discount\" >= 0");
            AddNotValid(migrationBuilder, "invoices", "CK_invoices_tax_non_negative", "\"Tax\" >= 0");
            AddNotValid(migrationBuilder, "invoice_items", "CK_invoice_items_quantity_positive", "\"Quantity\" > 0");
            AddNotValid(migrationBuilder, "bookings", "CK_bookings_attendee_count_positive", "\"AttendeeCount\" IS NULL OR \"AttendeeCount\" > 0");
            AddNotValid(migrationBuilder, "bookings", "CK_bookings_end_after_start", "\"EndTime\" > \"StartTime\"");
        }

        private static void AddNotValid(MigrationBuilder migrationBuilder, string table, string name, string sql) =>
            migrationBuilder.Sql($"ALTER TABLE \"{table}\" ADD CONSTRAINT \"{name}\" CHECK ({sql}) NOT VALID;");

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_purchase_order_items_quantity_positive",
                table: "PurchaseOrderItems");

            migrationBuilder.DropCheckConstraint(
                name: "CK_purchase_order_items_received_in_range",
                table: "PurchaseOrderItems");

            migrationBuilder.DropCheckConstraint(
                name: "CK_purchase_order_items_unit_price_non_negative",
                table: "PurchaseOrderItems");

            migrationBuilder.DropCheckConstraint(
                name: "CK_invoices_discount_non_negative",
                table: "invoices");

            migrationBuilder.DropCheckConstraint(
                name: "CK_invoices_tax_non_negative",
                table: "invoices");

            migrationBuilder.DropCheckConstraint(
                name: "CK_invoice_items_quantity_positive",
                table: "invoice_items");

            migrationBuilder.DropCheckConstraint(
                name: "CK_bookings_attendee_count_positive",
                table: "bookings");

            migrationBuilder.DropCheckConstraint(
                name: "CK_bookings_end_after_start",
                table: "bookings");
        }
    }
}
