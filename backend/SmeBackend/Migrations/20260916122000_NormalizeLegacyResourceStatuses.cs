using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations;

public partial class NormalizeLegacyResourceStatuses : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            UPDATE resources
            SET "Status" = 'Available'
            WHERE "Status" = 'Active';
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            UPDATE resources
            SET "Status" = 'Active'
            WHERE "Status" = 'Available';
            """);
    }
}
