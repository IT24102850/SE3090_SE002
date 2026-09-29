using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddPlatformSubscriptionBilling : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "platform_addons",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Tagline = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    CreditType = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Quantity = table.Column<int>(type: "integer", nullable: false),
                    ExpiryDays = table.Column<int>(type: "integer", nullable: false),
                    PricesJson = table.Column<string>(type: "jsonb", nullable: false),
                    Category = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    IsBestValue = table.Column<bool>(type: "boolean", nullable: false),
                    SavingsPercent = table.Column<int>(type: "integer", nullable: false),
                    MinimumTier = table.Column<int>(type: "integer", nullable: false),
                    IsPublic = table.Column<bool>(type: "boolean", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_addons", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_credit_entries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreditType = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Delta = table.Column<int>(type: "integer", nullable: false),
                    Remaining = table.Column<int>(type: "integer", nullable: false),
                    Reason = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    InvoiceId = table.Column<Guid>(type: "uuid", nullable: true),
                    Detail = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_credit_entries", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_invoices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Number = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    PlanCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    Period = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    Subtotal = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Discount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Tax = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Total = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    LinesJson = table.Column<string>(type: "jsonb", nullable: false),
                    PromotionCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    IssuedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    DueAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    PaidAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    PeriodStart = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    PeriodEnd = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_invoices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_platform_invoices_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "platform_plans",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Tier = table.Column<int>(type: "integer", nullable: false),
                    Tagline = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    HighlightsJson = table.Column<string>(type: "jsonb", nullable: false),
                    LimitsJson = table.Column<string>(type: "jsonb", nullable: false),
                    IsPublic = table.Column<bool>(type: "boolean", nullable: false),
                    IsMostPopular = table.Column<bool>(type: "boolean", nullable: false),
                    TrialDays = table.Column<int>(type: "integer", nullable: false),
                    IsRetired = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_plans", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_promotion_redemptions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PromotionId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    InvoiceId = table.Column<Guid>(type: "uuid", nullable: true),
                    Code = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    DiscountAmount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_promotion_redemptions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_promotions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    Kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    PercentOff = table.Column<int>(type: "integer", nullable: true),
                    AmountOff = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    AmountCurrency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    PlanCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    Period = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Terms = table.Column<int>(type: "integer", nullable: false),
                    StartsAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    EndsAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    MaxRedemptions = table.Column<int>(type: "integer", nullable: false),
                    Redemptions = table.Column<int>(type: "integer", nullable: false),
                    NewTenantsOnly = table.Column<bool>(type: "boolean", nullable: false),
                    LapsedTenantsOnly = table.Column<bool>(type: "boolean", nullable: false),
                    AutoApply = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_promotions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_subscription_events",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    SubscriptionId = table.Column<Guid>(type: "uuid", nullable: true),
                    EventType = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    FromPlanCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    ToPlanCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    Period = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    ActorEmail = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    Detail = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_subscription_events", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_usage_counters",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Metric = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    PeriodKey = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    Used = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_usage_counters", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "platform_payments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    InvoiceId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    Method = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Provider = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ExternalId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    GatewayResponse = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    PaidAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    SettlementCurrency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    SettlementAmount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    ExchangeRate = table.Column<decimal>(type: "numeric(18,6)", precision: 18, scale: 6, nullable: true),
                    IntentJson = table.Column<string>(type: "jsonb", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_payments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_platform_payments_platform_invoices_InvoiceId",
                        column: x => x.InvoiceId,
                        principalTable: "platform_invoices",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "platform_plan_prices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    Period = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    MonthlyEquivalent = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    SavingsPercent = table.Column<int>(type: "integer", nullable: false),
                    IsBestValue = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_plan_prices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_platform_plan_prices_platform_plans_PlanId",
                        column: x => x.PlanId,
                        principalTable: "platform_plans",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "platform_subscriptions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                    PlanCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Tier = table.Column<int>(type: "integer", nullable: false),
                    PriceId = table.Column<Guid>(type: "uuid", nullable: true),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Period = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    CurrentPeriodStart = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CurrentPeriodEnd = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    TrialEndsAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    TrialUsedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    AutoRenew = table.Column<bool>(type: "boolean", nullable: false),
                    CancelAtPeriodEnd = table.Column<bool>(type: "boolean", nullable: false),
                    CancelRequestedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CancelReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    GraceEndsAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    FailedRenewalAttempts = table.Column<int>(type: "integer", nullable: false),
                    ExtraSeats = table.Column<int>(type: "integer", nullable: false),
                    PromotionCode = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    DiscountAmount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    IsComplimentary = table.Column<bool>(type: "boolean", nullable: false),
                    ComplimentaryReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    LastPaymentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    StartedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_platform_subscriptions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_platform_subscriptions_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_platform_subscriptions_platform_plans_PlanId",
                        column: x => x.PlanId,
                        principalTable: "platform_plans",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_platform_addons_Code",
                table: "platform_addons",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_credit_entries_TenantId_CreditType_ExpiresAt",
                table: "platform_credit_entries",
                columns: new[] { "TenantId", "CreditType", "ExpiresAt" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_invoices_Number",
                table: "platform_invoices",
                column: "Number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_invoices_Status",
                table: "platform_invoices",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_platform_invoices_TenantId_IssuedAt",
                table: "platform_invoices",
                columns: new[] { "TenantId", "IssuedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_payments_InvoiceId",
                table: "platform_payments",
                column: "InvoiceId");

            migrationBuilder.CreateIndex(
                name: "IX_platform_payments_Provider_ExternalId",
                table: "platform_payments",
                columns: new[] { "Provider", "ExternalId" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_payments_TenantId_Status",
                table: "platform_payments",
                columns: new[] { "TenantId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_plan_prices_PlanId_Currency_Period",
                table: "platform_plan_prices",
                columns: new[] { "PlanId", "Currency", "Period" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_plans_Code",
                table: "platform_plans",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_plans_Tier",
                table: "platform_plans",
                column: "Tier");

            migrationBuilder.CreateIndex(
                name: "IX_platform_promotion_redemptions_TenantId_PromotionId",
                table: "platform_promotion_redemptions",
                columns: new[] { "TenantId", "PromotionId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_promotions_Code",
                table: "platform_promotions",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscription_events_EventType",
                table: "platform_subscription_events",
                column: "EventType");

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscription_events_TenantId_CreatedAt",
                table: "platform_subscription_events",
                columns: new[] { "TenantId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscriptions_PlanId",
                table: "platform_subscriptions",
                column: "PlanId");

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscriptions_Status",
                table: "platform_subscriptions",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscriptions_TenantId",
                table: "platform_subscriptions",
                column: "TenantId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_platform_subscriptions_Tier_CurrentPeriodEnd",
                table: "platform_subscriptions",
                columns: new[] { "Tier", "CurrentPeriodEnd" });

            migrationBuilder.CreateIndex(
                name: "IX_platform_usage_counters_TenantId_Metric_PeriodKey",
                table: "platform_usage_counters",
                columns: new[] { "TenantId", "Metric", "PeriodKey" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "platform_addons");

            migrationBuilder.DropTable(
                name: "platform_credit_entries");

            migrationBuilder.DropTable(
                name: "platform_payments");

            migrationBuilder.DropTable(
                name: "platform_plan_prices");

            migrationBuilder.DropTable(
                name: "platform_promotion_redemptions");

            migrationBuilder.DropTable(
                name: "platform_promotions");

            migrationBuilder.DropTable(
                name: "platform_subscription_events");

            migrationBuilder.DropTable(
                name: "platform_subscriptions");

            migrationBuilder.DropTable(
                name: "platform_usage_counters");

            migrationBuilder.DropTable(
                name: "platform_invoices");

            migrationBuilder.DropTable(
                name: "platform_plans");
        }
    }
}
