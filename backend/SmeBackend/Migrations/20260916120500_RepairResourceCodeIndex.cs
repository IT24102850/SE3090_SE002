using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations;

public partial class RepairResourceCodeIndex : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            DROP INDEX IF EXISTS "IX_resources_Code";
            CREATE UNIQUE INDEX IF NOT EXISTS "IX_resources_TenantId_Code"
                ON resources ("TenantId", "Code");
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            DROP INDEX IF EXISTS "IX_resources_TenantId_Code";
            CREATE UNIQUE INDEX IF NOT EXISTS "IX_resources_Code"
                ON resources ("Code");
            """);
    }
}
