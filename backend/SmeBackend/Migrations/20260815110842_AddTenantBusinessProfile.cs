using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantBusinessProfile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Amenities",
                table: "Tenants",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "AverageRating",
                table: "Tenants",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BusinessHours",
                table: "Tenants",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ContactEmail",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ContactPhone",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CoverImageUrl",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GalleryImageUrls",
                table: "Tenants",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ProfileUpdatedAt",
                table: "Tenants",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ReviewCount",
                table: "Tenants",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ShortTagline",
                table: "Tenants",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SocialLinks",
                table: "Tenants",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Website",
                table: "Tenants",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Amenities",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "AverageRating",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "BusinessHours",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "ContactEmail",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "ContactPhone",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "CoverImageUrl",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "Description",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "GalleryImageUrls",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "ProfileUpdatedAt",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "ReviewCount",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "ShortTagline",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "SocialLinks",
                table: "Tenants");

            migrationBuilder.DropColumn(
                name: "Website",
                table: "Tenants");
        }
    }
}
