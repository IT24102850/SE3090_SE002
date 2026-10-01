using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <summary>
    /// Makes double booking impossible at the database, not merely unlikely.
    ///
    /// Until now two requests for the same slot could both pass the C# check
    /// in Availability.HasConflictAsync and both be written: the check and the
    /// insert are not atomic. A PostgreSQL EXCLUDE constraint closes that
    /// window - the second transaction is refused by the engine itself,
    /// whatever code path, service instance or psql session it came from.
    ///
    /// Why a flag column: the constraint is backed by an index, and an index
    /// cannot join to another table. Whether a resource is taken whole or
    /// sells seats lives in resources/booking_types/departures, so the one
    /// bit is denormalised onto the booking (Shared/BookingExclusivity.cs).
    ///
    /// Why no hold-expiry term: index predicates must be IMMUTABLE, so now()
    /// cannot appear. A PendingPayment row therefore blocks its slot until
    /// BookingHoldExpiryService flips it to Expired, which it does within
    /// about 2.5 minutes. The database is briefly stricter than the API -
    /// it fails closed, never open.
    /// </summary>
    public partial class AddBookingOverlapExclusion : Migration
    {
        /// <summary>
        /// The statuses that hold a slot, matching Availability.HoldingSeats.
        /// Rejected is included because the single-booking path has always
        /// treated a rejected booking as still occupying its slot.
        /// </summary>
        private static string Active(string t) => $@"
            {t}""OccupiesResourceExclusively""
            AND {t}""DeletedAt"" IS NULL
            AND {t}""Status"" NOT IN ('Cancelled', 'WeatherCancelled', 'Expired')";

        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "OccupiesResourceExclusively",
                table: "bookings",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            // A gist index over (uuid, range) needs btree_gist for the uuid half.
            migrationBuilder.Sql(@"CREATE EXTENSION IF NOT EXISTS btree_gist;");

            // Backfill: a booking is shared - and so exempt - when its
            // departure, resource or booking type declares a capacity above
            // one, in the same order CapacityRules.Resolve applies them.
            migrationBuilder.Sql(@"
                UPDATE bookings b
                SET ""OccupiesResourceExclusively"" = false
                WHERE COALESCE(
                        (SELECT d.""LicensedCapacity"" FROM departures d
                          WHERE d.""Id"" = b.""DepartureId"" AND d.""LicensedCapacity"" > 0),
                        -- CustomAttributes is jsonb, so it is read directly;
                        -- jsonb_typeof guards against a capacity held as a
                        -- string or an object, which ::int would choke on.
                        (SELECT CASE
                                  WHEN jsonb_typeof(r.""CustomAttributes"" -> 'capacity') = 'number'
                                    THEN (r.""CustomAttributes"" ->> 'capacity')::int
                                END
                           FROM resources r WHERE r.""Id"" = b.""ResourceId""),
                        (SELECT NULLIF(r.""Capacity"", 0) FROM resources r WHERE r.""Id"" = b.""ResourceId""),
                        (SELECT NULLIF(t.""MaxParticipants"", 0) FROM booking_types t
                          WHERE t.""Id"" = b.""BookingTypeId""),
                        1) > 1;");

            // Any overlap that predates this rule is grandfathered rather than
            // deleted: the later row of each overlapping pair is exempted, so
            // the constraint can be created without destroying a real booking.
            // The count is raised as a warning for staff to resolve; every
            // booking written from now on is protected.
            migrationBuilder.Sql($@"
                DO $$
                DECLARE exempted int;
                BEGIN
                    WITH overlapping AS (
                        SELECT later.""Id""
                        FROM bookings later
                        JOIN bookings earlier
                          ON earlier.""ResourceId"" = later.""ResourceId""
                         AND earlier.""Id"" <> later.""Id""
                         AND tstzrange(earlier.""StartTime"", earlier.""EndTime"", '[)')
                             && tstzrange(later.""StartTime"", later.""EndTime"", '[)')
                         AND ({Active("earlier.")})
                         AND (later.""CreatedAt"", later.""Id"") > (earlier.""CreatedAt"", earlier.""Id"")
                        WHERE {Active("later.")}
                    )
                    UPDATE bookings SET ""OccupiesResourceExclusively"" = false
                    WHERE ""Id"" IN (SELECT ""Id"" FROM overlapping);
                    GET DIAGNOSTICS exempted = ROW_COUNT;
                    IF exempted > 0 THEN
                        RAISE WARNING 'AddBookingOverlapExclusion: % pre-existing overlapping booking(s) exempted from the new constraint; they need manual review.', exempted;
                    END IF;
                END $$;");

            migrationBuilder.Sql($@"
                ALTER TABLE bookings
                ADD CONSTRAINT ""EX_bookings_no_overlapping_exclusive""
                EXCLUDE USING gist (
                    ""ResourceId"" WITH =,
                    tstzrange(""StartTime"", ""EndTime"", '[)') WITH &&
                ) WHERE ({Active(string.Empty)});");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"ALTER TABLE bookings DROP CONSTRAINT IF EXISTS ""EX_bookings_no_overlapping_exclusive"";");
            migrationBuilder.DropColumn(
                name: "OccupiesResourceExclusively",
                table: "bookings");
        }
    }
}
