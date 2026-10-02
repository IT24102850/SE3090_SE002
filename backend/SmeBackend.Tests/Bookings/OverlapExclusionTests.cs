using Microsoft.EntityFrameworkCore;
using Npgsql;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using Testcontainers.PostgreSql;

namespace SmeBackend.Tests.Bookings;

/// <summary>
/// Proves the database itself refuses a double booking, against real
/// PostgreSQL (migration AddBookingOverlapExclusion).
///
/// The C# check in Availability.HasConflictAsync reads, then writes; between
/// those two steps another request can write the same slot. These tests fire
/// genuinely concurrent inserts, so they fail if the exclusion constraint is
/// missing - which is the whole point of having it.
/// </summary>
public sealed class OverlapExclusionTests
{
    private const string NoDocker = "Docker is not available, so the PostgreSQL Testcontainers test cannot run here (it runs in CI).";

    private static readonly DateTime SlotStart = new(2026, 11, 2, 9, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime SlotEnd = new(2026, 11, 2, 10, 0, 0, DateTimeKind.Utc);

    [SkippableFact]
    public async Task FiftyRacingRequestsForTheSameSlot_ProduceExactlyOneBooking()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);

            // Each task owns its own context and connection, so these are real
            // concurrent transactions rather than one serialized DbContext.
            var attempts = await Task.WhenAll(Enumerable.Range(0, 50).Select(async _ =>
            {
                await using var db = CreateDbContext(connection);
                db.Bookings.Add(NewBooking(seed));
                try
                {
                    await db.SaveChangesAsync();
                    return null as string;
                }
                catch (DbUpdateException e) when (e.InnerException is PostgresException pg)
                {
                    return pg.SqlState;
                }
            }));

            var winners = attempts.Count(state => state is null);
            var refused = attempts.Count(state => state == PostgresErrorCodes.ExclusionViolation);

            Assert.Equal(1, winners);
            Assert.Equal(49, refused);

            await using var verify = CreateDbContext(connection);
            Assert.Equal(1, await verify.Bookings.IgnoreQueryFilters().CountAsync());
        }
    }

    [SkippableFact]
    public async Task AnOverlappingBookingOnTheSameResource_IsRefusedWithExclusionViolation()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);
            await using var db = CreateDbContext(connection);

            db.Bookings.Add(NewBooking(seed));
            await db.SaveChangesAsync();

            // Starts inside the first booking's hour.
            db.Bookings.Add(NewBooking(seed, start: SlotStart.AddMinutes(30), end: SlotEnd.AddMinutes(30)));

            var error = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
            Assert.Equal(PostgresErrorCodes.ExclusionViolation, ((PostgresException)error.InnerException!).SqlState);
        }
    }

    [SkippableFact]
    public async Task BackToBackBookingsAreAllowed_BecauseTheRangeExcludesItsEnd()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);
            await using var db = CreateDbContext(connection);

            db.Bookings.Add(NewBooking(seed));
            db.Bookings.Add(NewBooking(seed, start: SlotEnd, end: SlotEnd.AddHours(1)));

            await db.SaveChangesAsync();

            Assert.Equal(2, await db.Bookings.IgnoreQueryFilters().CountAsync());
        }
    }

    [SkippableFact]
    public async Task ASharedResourceStillAcceptsOverlappingBookings()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);
            await using var db = CreateDbContext(connection);

            // A boat selling seats: the flag is false, so the constraint's
            // predicate does not cover these rows and they may overlap.
            db.Bookings.Add(NewBooking(seed, exclusive: false));
            db.Bookings.Add(NewBooking(seed, exclusive: false));

            await db.SaveChangesAsync();

            Assert.Equal(2, await db.Bookings.IgnoreQueryFilters().CountAsync());
        }
    }

    [SkippableFact]
    public async Task CancellingABooking_FreesTheSlotForSomeoneElse()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);
            await using var db = CreateDbContext(connection);

            var first = NewBooking(seed);
            db.Bookings.Add(first);
            await db.SaveChangesAsync();

            first.Status = BookingStatus.Cancelled;
            await db.SaveChangesAsync();

            db.Bookings.Add(NewBooking(seed));
            await db.SaveChangesAsync();

            Assert.Equal(1, await db.Bookings.IgnoreQueryFilters()
                .CountAsync(b => b.Status == BookingStatus.Confirmed));
        }
    }

    [SkippableFact]
    public async Task TheSameSlotOnADifferentResource_IsFine()
    {
        var container = await StartPostgresAsync();
        Skip.If(container is null, NoDocker);

        await using (container)
        {
            var connection = container.GetConnectionString();
            var seed = await SeedAsync(connection);
            await using var db = CreateDbContext(connection);

            var other = new Resource
            {
                TenantId = seed.TenantId,
                BranchId = seed.BranchId,
                Name = "Room 2",
            };
            db.Resources.Add(other);
            await db.SaveChangesAsync();

            db.Bookings.Add(NewBooking(seed));
            db.Bookings.Add(NewBooking(seed with { ResourceId = other.Id }));

            await db.SaveChangesAsync();

            Assert.Equal(2, await db.Bookings.IgnoreQueryFilters().CountAsync());
        }
    }

    private sealed record Seed(Guid TenantId, Guid BranchId, Guid ResourceId, Guid BookingTypeId, Guid UserId);

    private static SmeBackend.Models.Booking NewBooking(
        Seed seed, DateTime? start = null, DateTime? end = null, bool exclusive = true) => new()
        {
            TenantId = seed.TenantId,
            ResourceId = seed.ResourceId,
            BookingTypeId = seed.BookingTypeId,
            BookedBy = seed.UserId,
            Title = "Consultation",
            StartTime = start ?? SlotStart,
            EndTime = end ?? SlotEnd,
            Status = BookingStatus.Confirmed,
            OccupiesResourceExclusively = exclusive,
        };

    private static async Task<Seed> SeedAsync(string connectionString)
    {
        await using var db = CreateDbContext(connectionString);
        await db.Database.MigrateAsync();

        var tenant = new Tenant { Name = "Race Clinic", BusinessType = "Clinic", IsActive = true };
        db.Tenants.Add(tenant);
        await db.SaveChangesAsync();

        var branch = new Branch { TenantId = tenant.Id, Name = "Main", IsActive = true };
        db.Branches.Add(branch);
        var user = new User
        {
            TenantId = tenant.Id,
            Email = "race@test.local",
            FullName = "Race Tester",
            PasswordHash = "x",
            Role = UserRole.Customer,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();

        var resource = new Resource
        {
            TenantId = tenant.Id,
            BranchId = branch.Id,
            Name = "Room 1",
        };
        var bookingType = new BookingType
        {
            TenantId = tenant.Id,
            Name = "Consultation",
            DefaultDurationMinutes = 60,
        };
        db.Resources.Add(resource);
        db.BookingTypes.Add(bookingType);
        await db.SaveChangesAsync();

        return new Seed(tenant.Id, branch.Id, resource.Id, bookingType.Id, user.Id);
    }

    private static async Task<PostgreSqlContainer?> StartPostgresAsync()
    {
        try
        {
            var container = new PostgreSqlBuilder()
                .WithImage("postgres:16-alpine")
                .WithDatabase("smebackend")
                .WithUsername("postgres")
                .WithPassword("postgres")
                .Build();

            await container.StartAsync();
            return container;
        }
        catch
        {
            return null;
        }
    }

    private static AppDbContext CreateDbContext(string connectionString) =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(connectionString).Options, new TenantContext());
}
