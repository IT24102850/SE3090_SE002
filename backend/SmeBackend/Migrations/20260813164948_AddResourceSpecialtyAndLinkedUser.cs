using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddResourceSpecialtyAndLinkedUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "LinkedUserId",
                table: "resources",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Specialty",
                table: "resources",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LinkedUserId",
                table: "resources");

            migrationBuilder.DropColumn(
                name: "Specialty",
                table: "resources");
        }
    }
}
