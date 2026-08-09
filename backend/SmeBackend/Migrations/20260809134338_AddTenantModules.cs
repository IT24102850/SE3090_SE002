using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantModules : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TenantModules",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    ModuleName = table.Column<string>(type: "text", nullable: false),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    ConfigJson = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TenantModules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TenantModules_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.UpdateData(
                table: "Branches",
                keyColumn: "Id",
                keyValue: new Guid("22222222-2222-2222-2222-222222222222"),
                columns: new[] { "CreatedAt", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 204, DateTimeKind.Utc).AddTicks(4988), new DateTime(2026, 8, 9, 13, 43, 37, 204, DateTimeKind.Utc).AddTicks(4989) });

            migrationBuilder.UpdateData(
                table: "Tenants",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111111"),
                columns: new[] { "CreatedAt", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 204, DateTimeKind.Utc).AddTicks(1530), new DateTime(2026, 8, 9, 13, 43, 37, 204, DateTimeKind.Utc).AddTicks(1530) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 395, DateTimeKind.Utc).AddTicks(9160), "$2a$11$9LRnTkmhHBWhwx4ywK8uBebvpUp3OVmPK5roILHcuvu3XtHGh9qkq", new DateTime(2026, 8, 9, 13, 43, 37, 395, DateTimeKind.Utc).AddTicks(9168) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 578, DateTimeKind.Utc).AddTicks(6204), "$2a$11$tazjBRyGmsXNo1sMSSm3CukHWWZpGmYso2XFWYtJOCQrj13Vysely", new DateTime(2026, 8, 9, 13, 43, 37, 578, DateTimeKind.Utc).AddTicks(6208) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("cccccccc-cccc-cccc-cccc-cccccccccccc"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 787, DateTimeKind.Utc).AddTicks(8428), "$2a$11$xKpHBPAUQt7S3qq5dZQwYenOOHkyNvgOVNQQJG3o8vWCZBx7k2J9q", new DateTime(2026, 8, 9, 13, 43, 37, 787, DateTimeKind.Utc).AddTicks(8434) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 13, 43, 37, 968, DateTimeKind.Utc).AddTicks(253), "$2a$11$DuOg3hKnw.VlyVPzrtjgEOcexUYudJ1nJdnlPaTHRkv2ZEITCeX/G", new DateTime(2026, 8, 9, 13, 43, 37, 968, DateTimeKind.Utc).AddTicks(258) });

            migrationBuilder.CreateIndex(
                name: "IX_TenantModules_TenantId_ModuleName",
                table: "TenantModules",
                columns: new[] { "TenantId", "ModuleName" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TenantModules");

            migrationBuilder.UpdateData(
                table: "Branches",
                keyColumn: "Id",
                keyValue: new Guid("22222222-2222-2222-2222-222222222222"),
                columns: new[] { "CreatedAt", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 230, DateTimeKind.Utc).AddTicks(2310), new DateTime(2026, 8, 9, 12, 9, 16, 230, DateTimeKind.Utc).AddTicks(2310) });

            migrationBuilder.UpdateData(
                table: "Tenants",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111111"),
                columns: new[] { "CreatedAt", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 229, DateTimeKind.Utc).AddTicks(8986), new DateTime(2026, 8, 9, 12, 9, 16, 229, DateTimeKind.Utc).AddTicks(8986) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 372, DateTimeKind.Utc).AddTicks(5104), "$2a$11$EIaLI3.KF/2qGiN87F1w1.qNByWPZBBC1m6gbl5gybsBe8cMXOAUq", new DateTime(2026, 8, 9, 12, 9, 16, 372, DateTimeKind.Utc).AddTicks(5109) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 599, DateTimeKind.Utc).AddTicks(9511), "$2a$11$BNeA3Oc2s8qQOIbU1sGsAuduc7d2qTUUswYWD5UGcBgbmZOeyXQ5i", new DateTime(2026, 8, 9, 12, 9, 16, 599, DateTimeKind.Utc).AddTicks(9516) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("cccccccc-cccc-cccc-cccc-cccccccccccc"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 778, DateTimeKind.Utc).AddTicks(3203), "$2a$11$v4DzEetQJUG7Sx8qpX3H9ejRREXahGL/Hyy9MN98KsQhEiA9nqnLu", new DateTime(2026, 8, 9, 12, 9, 16, 778, DateTimeKind.Utc).AddTicks(3208) });

            migrationBuilder.UpdateData(
                table: "Users",
                keyColumn: "Id",
                keyValue: new Guid("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                columns: new[] { "CreatedAt", "PasswordHash", "UpdatedAt" },
                values: new object[] { new DateTime(2026, 8, 9, 12, 9, 16, 960, DateTimeKind.Utc).AddTicks(832), "$2a$11$rMhm0Fg7WRPNSFGsD3M1XObBbH.SwwKiSo6xFyuNvXsXlnT./zaA6", new DateTime(2026, 8, 9, 12, 9, 16, 960, DateTimeKind.Utc).AddTicks(837) });
        }
    }
}
