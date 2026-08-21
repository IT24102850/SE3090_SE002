using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class BackfillTenantCutoffDefaults : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // The previous migration added these columns as NOT NULL DEFAULT 0,
            // which silently zeroed out the cutoff protection for every
            // already-onboarded tenant. Back-fill to the model's real
            // defaults (2h reschedule / 1h cancel) for rows still at 0.
            migrationBuilder.Sql(
                "UPDATE \"Tenants\" SET \"RescheduleCutoffHours\" = 2 WHERE \"RescheduleCutoffHours\" = 0;");
            migrationBuilder.Sql(
                "UPDATE \"Tenants\" SET \"CancellationCutoffHours\" = 1 WHERE \"CancellationCutoffHours\" = 0;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Not reversible (original per-row values weren't 0 by choice — no way to distinguish
            // a genuine 0h policy from the backfill), intentionally left as a no-op.
        }
    }
}
