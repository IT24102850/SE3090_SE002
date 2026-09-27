using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using SmeBackend.Data;

#nullable disable

namespace SmeBackend.Migrations;

/// Adds the timestamp the clinic dashboard's wait-time KPI is built on.
/// Additive and nullable: every existing booking keeps behaving exactly as
/// it did; only bookings moved to InProgress from now on get a value.
///
/// Carries the [DbContext]/[Migration] attributes explicitly because it is
/// hand-written: EF discovers migrations by the attribute, not the file
/// name, and the snapshot has been updated by hand to match.
[DbContext(typeof(AppDbContext))]
[Migration("20260918090000_AddBookingConsultationStartedAt")]
public partial class AddBookingConsultationStartedAt : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTime>(
            name: "ConsultationStartedAt",
            table: "bookings",
            type: "timestamp with time zone",
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "ConsultationStartedAt",
            table: "bookings");
    }
}
