using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The anonymous half of the website booking widget.
///
/// A business drops one script tag on its own site (frontend/public/embed.js),
/// which mounts the Unify booking form in an iframe. That form reads what is
/// bookable from <see cref="Catalog"/> and submits through <see cref="Create"/>.
/// The booking lands in the tenant's dashboard as an ordinary Pending
/// reservation with Source = "Website", so the channel-split report and the
/// departure manifest see it like any other sale.
///
/// Nothing here trusts the caller: the tenant comes from the route, every
/// referenced row is checked to belong to that tenant, prices come from the
/// booking type's config (never the request), and the same
/// <see cref="Availability"/> rules as the authenticated endpoints decide
/// whether the seats exist.
[ApiController]
[Route("api/public/booking")]
[AllowAnonymous]
public class PublicBookingController : ControllerBase
{
    public const string RateLimitPolicy = "public-booking";
    public const string Source = "Website";

    private const int MaxLookaheadDays = 90;
    private const int MaxSeatsPerBooking = 20;

    private readonly AppDbContext _db;
    public PublicBookingController(AppDbContext db) => _db = db;

    /// <summary>What a visitor can book: the business, its ticket prices, and either its upcoming departures or its bookable resources.</summary>
    [HttpGet("{tenantId:guid}/catalog")]
    public async Task<IActionResult> Catalog(Guid tenantId, [FromQuery] int days = 45)
    {
        var tenant = await _db.Tenants.AsNoTracking()
            .Where(t => t.Id == tenantId)
            .Select(t => new { t.Id, t.Name, t.LogoUrl, t.Website, t.BusinessType, t.SubType, t.ContactPhone })
            .FirstOrDefaultAsync();
        if (tenant == null) return NotFound(new { message = "Business not found." });

        days = Math.Clamp(days, 1, MaxLookaheadDays);
        var now = DateTime.UtcNow;
        var horizon = now.AddDays(days);

        var bookingTypes = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.Status == BookingTypeStatus.Active)
            .OrderBy(bt => bt.Name)
            .ToListAsync();

        // Anonymous requests have no tenant context, so the global
        // TenantId == CurrentTenantId filters on Resource (and, through the
        // required Resource navigation, on Departure) would return nothing.
        // Filters off, and the same tenant + soft-delete conditions written
        // out by hand.
        var departures = await _db.Departures.AsNoTracking()
            .IgnoreQueryFilters()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .Where(d => d.TenantId == tenantId
                && d.DeletedAt == null
                && d.Resource.DeletedAt == null
                && (d.BookingType == null || d.BookingType.DeletedAt == null)
                && d.Status == DepartureStatus.Scheduled
                && d.ScheduledDeparture > now
                && d.ScheduledDeparture <= horizon)
            .OrderBy(d => d.ScheduledDeparture)
            .ToListAsync();

        // Seats sold per sailing, in one query rather than one per departure.
        var departureIds = departures.Select(d => d.Id).ToList();
        var sold = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId != null
                && departureIds.Contains(b.DepartureId.Value)
                && b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected)
            .Select(b => new { b.DepartureId, b.TicketBreakdown, b.AttendeeCount })
            .ToListAsync();
        var paxByDeparture = sold
            .GroupBy(b => b.DepartureId!.Value)
            .ToDictionary(g => g.Key, g => g.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount)));

        var resources = await _db.Resources.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && r.Status == ResourceStatus.Available)
            .OrderBy(r => r.Name)
            .Select(r => new { r.Id, r.Name, r.Category, r.Description })
            .ToListAsync();

        return Ok(new
        {
            tenant = new { tenant.Id, tenant.Name, tenant.LogoUrl, tenant.Website, tenant.BusinessType, tenant.SubType, tenant.ContactPhone },
            bookingTypes = bookingTypes.Select(bt =>
            {
                var config = JsonAttributes.Root(bt.ConfigJson);
                return new
                {
                    bt.Id,
                    bt.Name,
                    bt.Description,
                    bt.DefaultDurationMinutes,
                    bt.RequiresApproval,
                    currency = JsonAttributes.String(config, "pricing.currency") ?? "LKR",
                    // Base (non-seasonal) prices, for the summary the visitor
                    // sees before they submit. The server re-prices on
                    // submission with the seasonal window for the actual date.
                    pricing = TicketPricing.KnownTypes.ToDictionary(
                        t => t.ToLowerInvariant(),
                        t => TicketPricing.UnitPriceFor(config, null, t)),
                };
            }),
            departures = departures.Select(d =>
            {
                var capacity = CapacityRules.Resolve(d.Resource, d.BookingType, d) ?? 0;
                var pax = paxByDeparture.GetValueOrDefault(d.Id);
                return new
                {
                    d.Id,
                    d.ResourceId,
                    vesselName = d.Resource?.Name ?? "Vessel",
                    d.BookingTypeId,
                    bookingTypeName = d.BookingType?.Name,
                    d.ScheduledDeparture,
                    d.ScheduledReturn,
                    capacity,
                    seatsRemaining = capacity > 0 ? Math.Max(capacity - pax, 0) : (int?)null,
                };
            }),
            resources,
        });
    }

    /// <summary>Creates a Pending booking from a visitor on the business's own website.</summary>
    [HttpPost("{tenantId:guid}")]
    [EnableRateLimiting(RateLimitPolicy)]
    public async Task<IActionResult> Create(Guid tenantId, [FromBody] PublicBookingRequest dto)
    {
        // Honeypot: real visitors never see this field, so anything in it is
        // a bot. Answer as if it worked so it does not learn to adapt.
        if (!string.IsNullOrWhiteSpace(dto.Website))
            return Ok(new { id = Guid.NewGuid(), status = "Pending" });

        var tenantExists = await _db.Tenants.AsNoTracking().AnyAsync(t => t.Id == tenantId);
        if (!tenantExists) return NotFound(new { message = "Business not found." });

        var lines = new List<TicketLine>
        {
            new() { Type = "Adult", Qty = Math.Max(0, dto.Adults) },
            new() { Type = "Child", Qty = Math.Max(0, dto.Children) },
            new() { Type = "Infant", Qty = Math.Max(0, dto.Infants) },
        }.Where(l => l.Qty > 0).ToList();
        var seats = lines.Sum(l => l.Qty);
        if (seats < 1)
            return BadRequest(new { message = "Add at least one ticket." });
        if (seats > MaxSeatsPerBooking)
            return BadRequest(new { message = $"For groups over {MaxSeatsPerBooking}, please contact the business directly." });
        if (dto.Adults < 1)
            return BadRequest(new { message = "At least one adult is required per booking." });

        // ── Where and when ──────────────────────────────────────────────
        Guid resourceId;
        Guid? bookingTypeId;
        Guid? departureId = null;
        DateTime start, end;
        string whereLabel;

        if (dto.DepartureId is { } depId)
        {
            var departure = await _db.Departures.AsNoTracking()
                .IgnoreQueryFilters()
                .Include(d => d.Resource)
                .FirstOrDefaultAsync(d => d.Id == depId && d.TenantId == tenantId && d.DeletedAt == null && d.Resource.DeletedAt == null);
            if (departure == null)
                return NotFound(new { message = "That departure is no longer available." });
            if (departure.Status != DepartureStatus.Scheduled || departure.ScheduledDeparture <= DateTime.UtcNow)
                return BadRequest(new { message = "That departure is no longer open for booking." });

            departureId = departure.Id;
            resourceId = departure.ResourceId;
            bookingTypeId = departure.BookingTypeId;
            start = departure.ScheduledDeparture;
            end = departure.ScheduledReturn;
            whereLabel = departure.Resource?.Name ?? "departure";
        }
        else
        {
            if (dto.ResourceId is null || dto.StartTime is null)
                return BadRequest(new { message = "Choose a departure, or a resource and a start time." });

            var resource = await _db.Resources.AsNoTracking()
                .IgnoreQueryFilters()
                .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.TenantId == tenantId && r.DeletedAt == null);
            if (resource == null)
                return NotFound(new { message = "That resource is not available." });

            resourceId = resource.Id;
            bookingTypeId = dto.BookingTypeId;
            start = DateTimeUtil.AsUtc(dto.StartTime.Value);
            if (start <= DateTime.UtcNow)
                return BadRequest(new { message = "Choose a time in the future." });
            end = default;
            whereLabel = resource.Name;
        }

        // Booking.BookingTypeId is required; a departure without one (or a
        // resource-slot booking that named none) falls back to the tenant's
        // first active type so the reservation still prices and lists.
        var bookingType = bookingTypeId.HasValue
            ? await _db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(bt => bt.Id == bookingTypeId && bt.TenantId == tenantId)
            : null;
        bookingType ??= await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.Status == BookingTypeStatus.Active)
            .OrderBy(bt => bt.CreatedAt)
            .FirstOrDefaultAsync();
        if (bookingType == null)
            return BadRequest(new { message = "This business has no bookable service configured yet." });
        if (end == default)
            end = start.AddMinutes(Math.Max(15, bookingType.DefaultDurationMinutes));

        var availability = await Availability.CheckAsync(
            _db, resourceId, bookingType.Id, departureId, start, end, seats, ignoreTenantFilters: true);
        if (availability.Error != null)
            return availability.IsCapacityFailure
                ? BadRequest(new { message = availability.Error, capacity = availability.Capacity, seatsRemaining = availability.SeatsRemaining })
                : Conflict(new { message = availability.Error });

        // ── Who ─────────────────────────────────────────────────────────
        // Booking.BookedBy must be a user, so the guest gets (or reuses) a
        // Customer account keyed on their email within this tenant. They
        // cannot sign in with it until they set a password - the hash is
        // random - but it means their bookings are already theirs if they
        // ever register on Unify with the same email.
        var email = dto.Email.Trim().ToLowerInvariant();
        var guest = await _db.Users
            .IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.TenantId == tenantId && u.Email.ToLower() == email);
        if (guest == null)
        {
            guest = new User
            {
                TenantId = tenantId,
                Email = email,
                FullName = dto.FullName.Trim(),
                Phone = dto.Phone.Trim(),
                Role = UserRole.Customer,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString("N")),
                IsActive = true,
            };
            _db.Users.Add(guest);
        }

        // ── The booking ─────────────────────────────────────────────────
        var priced = TicketPricing.Price(lines, bookingType, start);
        var formData = JsonSerializer.Serialize(new
        {
            channel = Source,
            guestName = dto.FullName.Trim(),
            guestEmail = email,
            guestPhone = dto.Phone.Trim(),
            specialRequests = string.IsNullOrWhiteSpace(dto.Notes) ? null : dto.Notes.Trim(),
            pageUrl = string.IsNullOrWhiteSpace(dto.PageUrl) ? null : dto.PageUrl.Trim(),
        });

        var booking = new Booking
        {
            TenantId = tenantId,
            ResourceId = resourceId,
            BookingTypeId = bookingType.Id,
            BookedBy = guest.Id,
            BookedFor = guest.Id,
            Title = $"{dto.FullName.Trim()} · website",
            Notes = string.IsNullOrWhiteSpace(dto.Notes) ? null : dto.Notes.Trim(),
            StartTime = start,
            EndTime = end,
            Status = BookingStatus.Pending,
            Priority = BookingPriority.Normal,
            AttendeeCount = priced.TotalQuantity,
            FormData = formData,
            DepartureId = departureId,
            TicketBreakdown = TicketPricing.Serialize(priced.Lines),
            Source = Source,
            TotalCost = priced.Total,
        };
        _db.Bookings.Add(booking);

        // Tenant-wide (UserId null) so every admin, manager and staff member
        // sees the new website booking in their bell, not just one person.
        NotificationHelper.Queue(_db, tenantId, null, "WebsiteBooking",
            "New website booking",
            $"{dto.FullName.Trim()} booked {seats} seat{(seats == 1 ? "" : "s")} on {whereLabel} for {start:ddd d MMM, HH:mm} via your website.");

        await _db.SaveChangesAsync();

        return Ok(new
        {
            id = booking.Id,
            reference = booking.Id.ToString("N")[..8].ToUpperInvariant(),
            status = booking.Status.ToString(),
            startTime = booking.StartTime,
            endTime = booking.EndTime,
            resourceName = whereLabel,
            tickets = priced.Lines,
            total = priced.Total,
            currency = priced.Currency,
            seasonLabel = priced.SeasonLabel,
            requiresApproval = true,
        });
    }
}

public class PublicBookingRequest
{
    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [Required, EmailAddress, MaxLength(200)]
    public string Email { get; set; } = string.Empty;

    [Required, MaxLength(40)]
    public string Phone { get; set; } = string.Empty;

    /// A fixed sailing (whale watching, safari jeep, ...). When set, the
    /// resource, service and times all come from it.
    public Guid? DepartureId { get; set; }

    /// Slot mode, for businesses without departures: which resource and when.
    public Guid? ResourceId { get; set; }
    public Guid? BookingTypeId { get; set; }
    public DateTime? StartTime { get; set; }

    [Range(0, 50)] public int Adults { get; set; }
    [Range(0, 50)] public int Children { get; set; }
    [Range(0, 50)] public int Infants { get; set; }

    [MaxLength(2000)]
    public string? Notes { get; set; }

    /// The page the widget was embedded on, for the operator's reference.
    [MaxLength(500)]
    public string? PageUrl { get; set; }

    /// Honeypot. Hidden from people; bots fill it.
    [MaxLength(200)]
    public string? Website { get; set; }
}
