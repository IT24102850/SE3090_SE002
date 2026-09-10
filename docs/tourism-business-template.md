# Universal Tourism Business Template

A reusable mapping from real Sri Lankan tourism business subtypes onto the
existing `Resource` / `BookingType` schema, so any tourism business - not
just whale watching - can be onboarded consistently without any DB schema
change. No new tables/columns are introduced here; everything below is
expressed through fields that already exist (`Resource.Category`,
`Resource.Specialty`, `Resource.HourlyRate`, `Resource.CustomAttributes`
JSONB, and `BookingType`).

## 1. Survey: tourism business archetypes in Sri Lanka

Sri Lankan tourism is not one shape of business - it spans wildlife
excursions, watersports schools, guided treks, rentals, cultural tours,
multi-day packages, wellness retreats, and transport. Grouping the real
market into archetypes keeps the template small while still covering
almost everything:

| Archetype | Real examples | Booking shape |
|---|---|---|
| A. Fixed-departure excursion | Whale watching (Mirissa, Trincomalee), safari jeep tours (Yala, Udawalawe, Wilpattu), river safari (Madu Ganga), deep-sea fishing charters | One vehicle, one or more scheduled daily departures, fixed duration |
| B. Instructor-led activity | Surf lessons (Weligama, Arugam Bay), diving/PADI courses (Hikkaduwa, Trincomalee, Nilaveli), white-water rafting (Kitulgala), cookery classes | One instructor/guide per session, duration = lesson length |
| C. Equipment rental | Surfboard/kayak/bike rental, snorkel gear, camping gear | Self-guided, duration = rental period, no instructor |
| D. Guided trek/hike | Adam's Peak, Ella Rock, Horton Plains, Knuckles Range | One guide, duration = hike length, often early-morning start |
| E. Cultural/heritage tour | Sigiriya/Kandy/Anuradhapura city tours, tea plantation tours, village tours | One guide or driver-guide, duration = tour length |
| F. Multi-day package | Round-Sri-Lanka tours, honeymoon packages | One vehicle+driver or coordinator, duration in days, high value -> approval required |
| G. Wellness/Ayurveda retreat | Spa treatments, Ayurveda programs | One therapist or treatment room, duration = session length |
| H. Homestay/eco-lodge | Village homestays, boutique eco-lodges | One room, duration = nights (or per-day booking type) |
| I. Villa/hotel | Boutique hotels, resort villas, private pool villas | One room (or whole villa), duration = nights |

## 2. `Resource.Category` mapping

| Archetype | `Category` | Notes |
|---|---|---|
| A. Fixed-departure excursion | `Vehicle` | One `Resource` per boat/jeep **and** per departure slot if there are multiple daily departures (see [[Mirissa Jetliner]] pattern: "Dawn Departure" and "Morning Cruise" are two separate `Resource` rows on the same boat type, each with its own `ResourceSchedule` window) |
| B. Instructor-led activity | `Staff` | One `Resource` per instructor, `LinkedUserId` to a Staff login so they see their own schedule |
| C. Equipment rental | `Equipment` | One `Resource` per rentable unit or per equipment type if pooled |
| D. Guided trek/hike | `Staff` | Same as B |
| E. Cultural/heritage tour | `Staff` | Same as B; use `Vehicle` instead if the tour is really "book the van", not "book the guide" |
| F. Multi-day package | `Vehicle` or `Other` | `Vehicle` when a specific car/van+driver is being booked; `Other` for packages with no single physical resource |
| G. Wellness/Ayurveda retreat | `Staff` (therapist) or `Room` (treatment room) | Pick whichever is the actual bottleneck resource |
| H. Homestay/eco-lodge | `Room` | Duration-based booking (nights), same as the Restaurant demo's table-booking pattern but with day-length slots |
| I. Villa/hotel | `Room` | Same as H; kept as a separate subtype since guest expectations (private pool, whole-villa booking) differ from a homestay |

## 3. Universal `CustomAttributes` JSON schema

This is a superset shape - every field is optional, fill in only what's real
for the business. It's consumed by the Domain Analysis Agent
(`agentic-ai-service/agents/domain_analysis_agent.py`) for ranking, so
richer data here means better "find me the best X" results later.

```jsonc
{
  "subtype": "WildlifeExcursion | WatersportsLesson | EquipmentRental | GuidedTrek | CulturalTour | MultiDayPackage | WellnessRetreat | Accommodation | VillaHotel",
  "capacity": 120,
  "pricing": { "adult": 7500, "child": 4000, "currency": "LKR" },
  "difficultyLevel": "Easy | Moderate | Challenging",
  "ageRestriction": "Above 12 years",
  "languagesSpoken": ["English", "Sinhala"],
  "includes": ["breakfast", "life jacket", "insurance"],
  "excludes": ["hotel pickup outside 3km radius"],
  "pickup": { "available": true, "radiusKm": 3, "pointsOfDeparture": ["Mirissa Harbour"] },
  "season": { "months": ["Nov", "Dec", "Jan", "Feb", "Mar", "Apr"], "weatherDependent": true },
  "certificationRequired": "PADI Open Water (for dive add-ons)",
  "rating": 4.8,
  "reviewCount": 1200
}
```

The same shape is also written to `BookingType.ConfigJson`, plus two keys
that only make sense there:

```jsonc
{
  "subType": "whaleWatching",          // the registry key - see section 8
  "bookingUnit": "Slot",
  "pricing": { "adult": 7500, "child": 4000, "infant": 0, "currency": "LKR" },
  "seasonalPricing": [
    { "label": "Peak", "months": ["Dec","Jan","Feb","Mar"], "offPeak": false,
      "pricing": { "adult": 9000, "child": 5000 } },
    { "label": "Off-peak", "months": ["May","Jun","Jul","Aug","Sep","Oct"], "offPeak": true,
      "pricing": { "adult": 6000, "child": 3000 } }
  ]
}
```

- `pricing.infant`, `seasonalPricing` and `category` are **additive**.
  `subType`, `pricing.adult`, `pricing.child`, `capacity` and `season` keep
  their exact names and meanings, because the Flutter app parses them - see
  section 8's compatibility note.
- `category` - what *kind of product* this is, as distinct from `subType`,
  which is what kind of *business* sells it:

  | Value | Meaning | Example |
  |---|---|---|
  | `tour` | A scheduled trip tied to a vessel departure | "Morning Whale Watching Tour", "Sunset Dolphin Cruise" |
  | `package` | A bundle sold as one product | "Whale Tour + Lunch + Hotel Transfer" |
  | `addon` | A per-booking extra | "Hotel Pickup", "Photo Package", "Snorkel Gear Rental" |

  The admin dashboard splits **Packages & Tours** (`tour` and `package`)
  from **Services & Add-ons** (`addon`) on this key alone. An absent,
  unrecognised or malformed value resolves to `tour`, deliberately: every
  product written before this convention existed is something the operator
  sells as a trip, and defaulting to `addon` instead would hide existing
  products in a section nobody has opened yet. No migration - it is jsonb.
- `seasonalPricing` - the first entry whose `months` contains the booking's
  month wins; a month named by no window falls through to base `pricing`. A
  window with no `months` never matches, so a half-written config degrades
  to base pricing rather than applying everywhere. `offPeak: true` (or a
  label containing "off") drives the "off-peak rate" badge in the admin and
  booking UI.

Field notes:
- `pricing.child` - omit entirely (not `0`) if there's no child rate; the
  mobile UI's price display is a null-check, not a zero-check (see
  `Resource.HourlyRate` - the same rule applies to anything derived from
  `CustomAttributes`).
- `season.months` - important for whale watching (Nov-Apr west coast) and
  surfing (opposite seasons on the east vs. west coast) where the
  "open weekly schedule" alone doesn't capture that the business is
  entirely closed for half the year. `ResourceScheduleException` can be
  used for known multi-week closures if exact dates are known; `season`
  in `CustomAttributes` is the general-purpose signal for the ranking
  agent when exact closure dates aren't tracked.
- `rating`/`reviewCount` - only set from a real, sourced number (e.g. a
  fetched TripAdvisor/Google rating). Don't fabricate a plausible-looking
  rating for a real, identifiable business - leave it unset if unknown,
  same standard applied when [[Mirissa Jetliner]] was seeded without one.

## 4. `BookingType` conventions

| Field | Convention |
|---|---|
| `DefaultDurationMinutes` | The **real** activity duration, not a generic default. This directly drives `SlotCalculator` - a 4-hour tour needs `240`, not `60`, or the customer will see it choppedinto misleadingly short bookable slots. |
| `RequiresApproval` | `true` for multi-day packages, large groups, or anything a human should confirm before it's locked in (mirrors the existing `>LKR 500` agent-approval threshold pattern) |
| `MaxParticipants` | Set to the resource's real capacity (boat/jeep/class size) |
| `BufferMinutesBefore/After` | Use for gear changeover / cleaning time on Equipment or Vehicle resources |

## 5. Reusable seeding pattern

`scripts/seed-tourism-template.ps1` generalizes the one-off
`seed-mirissa-jetliner.ps1` script into a reusable scaffold: each business
is a hashtable of resources that can each carry **their own** schedule
window (needed for archetype A's multiple daily departures) instead of one
shared weekly schedule for the whole business. Add a new business to the
`$tourismBusinesses` array following the shape already used for Mirissa
Jetliner and run the script - no code changes needed for a new business,
only data.

## 6. Known limitation

The archetypes above still assume "book a resource for a block of time" -
that's the one thing every Sri Lankan tourism business in this survey has
in common, and it's what the existing `Resource`/`BookingType`/
`SlotCalculator` model already does well.

- ~~**Per-ticket-type pricing within one booking**~~ - **resolved.** A
  booking now carries a `TicketBreakdown` jsonb column
  (`[{ "type": "Adult", "qty": 2, "unitPrice": 7500 }, ...]`) priced
  server-side from `BookingType.ConfigJson`'s `pricing.*` and
  `seasonalPricing` blocks. "2 adults + 1 child" is one reservation with one
  total, capacity is consumed by the summed headcount (infants included),
  and revenue reports split by ticket type. A booking with no breakdown
  behaves exactly as it did before: one unit, one price.
- **Multi-resource packages** (e.g. a round-island tour bundling a
  vehicle + multiple hotel nights) - still open. Currently modelled as a
  single `Other`-category resource representing "the package", which is a
  simplification, not a true composition of several bookable resources.

The remaining one is flagged here rather than silently worked around,
consistent with the scoped-out limitation already noted for the agentic AI
subsystem.

## 7. Shared-capacity resources

The booking engine's original rule is **exclusive occupancy**: any overlap on
a resource is a conflict. That is right for a consulting room or a hire car,
and wrong for a 120-seat whale-watching boat, where twenty separate
reservations share one sailing.

Capacity sharing is therefore **opt-in per resource**, and applies only where
the operator has actually declared a passenger capacity greater than one -
`Resource.CustomAttributes.capacity`, then `Resource.Capacity`, then
`BookingType.MaxParticipants`, most specific first. A resource with no such
figure keeps exclusive conflict detection byte for byte, which is every
resource that predates this and every genuinely one-at-a-time resource.

Where sharing is on:
- overlapping bookings are **summed against the capacity** instead of
  rejected;
- a booking that would exceed the licensed capacity is **rejected** (400,
  with the seats remaining), and one that would take the sailing to **90% or
  more warns without blocking** - the sale goes through and the board flags
  the departure as nearly full;
- the per-resource "max booked hours/day" rule measures the **union** of
  booked intervals rather than their sum, so twenty guests on one four-hour
  sailing is four vessel-hours, not eighty. On an exclusive resource nothing
  overlaps, so this is arithmetically identical to the sum it replaced.

## 8. Sub-type dashboard registry

Every tenant's admin dashboard is chosen by its `Tenant.SubType` string
through a registry that mirrors the Flutter app's, one file per side:

| | React (web admin) | Flutter (customer app) |
|---|---|---|
| Vocabulary | `frontend/src/features/dashboard/subtypes/tourismSubTypes.ts` | `mobile/sme_mobile/lib/models/tourism_subtype.dart` |
| Config type | `.../subtypes/SubtypeDashboardConfig.ts` | `.../models/subtype_dashboard_config.dart` |
| The registry | `.../subtypes/subtypeRegistry.ts` | `.../registry/tourism_dashboard_registry.dart` |

One config per sub-type defines its terminology (`resourceTermPlural`,
`bookingTermPlural`, `equipmentTerm`, `heroActionLabel`), theme colour and
icon, KPI card definitions, resource table columns, booking-form extra
fields, and which shared modules apply (`weather`, `departures`,
`sightings`, `safety`, `approvals`, `ticketTypes`).

`frontend/src/features/dashboard/DashboardRouter.tsx` resolves the tenant's
SubType and picks the screen:

- **unset, unrecognised, or a non-Tourism business** -> the generic
  `CalendarDashboardPage` exactly as before, with every module off;
- **a sub-type whose config turns the `departures` module on** -> that
  sub-type's own operational dashboard (only `whaleWatching` today);
- **any other recognised sub-type** -> its terminology and KPI strip above
  the same calendar.

Adding a sub-type is one key in `tourismSubTypes.ts` and one config entry in
`subtypeRegistry.ts`. No screen component changes.

A config may also carry `navOverrides`, which renames sidebar entries for
that sub-type - whale watching maps `/dashboard` to "Departure Board",
`/bookings` to "Reservations & Manifest" and `/resources` to "Vessels &
Crew". Only the label and icon change; paths never do, so
`scripts/check-nav-parity.mjs` still matches every route.

**Resolving the sub-type.** `features/dashboard/subtype.ts` exposes
`WHALE_WATCHING_SUBTYPE`, `getTenantSubtype()` and `resetSubtypeCache()` for
callers outside React or that need the answer before any hook has run;
`useSubtypeConfig()` is the hook form. Both read **`GET /api/tenant`**, not
the business-profile endpoint: the profile response is the public listing
projection and carries no `SubType` at all, so resolving from it would
return undefined for every tenant and drop everybody onto the generic
dashboard.

`resetSubtypeCache()` and `bookingApi.util.resetApiState()` are both
dispatched on logout. Without them the next tenant to sign in on the same
browser inherits the previous tenant's dashboard, sidebar labels and cached
list data until a hard refresh.

**Product sections.** The whale-watching dashboard's Packages & Tours and
Services & Add-ons sections are driven entirely by `category` above, via
`features/dashboard/productCategory.ts`. A product whose `subType` is unset
is included rather than dropped - it is still that tenant's product, and
hiding it from the operator's own dashboard would be worse than showing one
too many.

**Compatibility.** The label strings in `TOURISM_SUB_TYPE_LABELS` must stay
identical to `TOURISM_SUB_TYPES` in `frontend/src/features/booking/types.ts`
(the registration dropdown, and therefore what is actually stored on the
tenant) and to `kTourismSubTypeLabels` in the Flutter app. A mismatch is
silent: the tenant registers fine and then quietly gets the generic
dashboard forever. `frontend/scripts/check-subtype-registry.mjs` runs on
every `npm run build` and fails the build if the four lists drift apart.

## 9. Departure operations (archetype A)

Fixed-departure excursions - whale watching boats, safari jeeps - get three
tables on top of the shared schema. None of them is reachable for a tenant
that has no rows in them, so every other business type is untouched.

| Table | What it holds |
|---|---|
| `departures` | One scheduled sailing: vessel, captain, `Crew` jsonb, `SafetyChecklist` jsonb, status (`Scheduled \| Boarding \| AtSea \| Returned \| CancelledWeather \| CancelledOther`), optional `LicensedCapacity` override |
| `sightings_logs` | One wildlife sighting: species, count, lat/lng, behaviour, photos. **Not whale-specific** - `SightingSpecies` spans marine *and* land wildlife, so a Yala operator's leopard sightings feed the same success-rate analytics |
| `weather_observations` | A wind / wave / visibility / sea-state reading. Entered by hand; the `Source` column exists so a future provider can write rows alongside the manual ones without a schema change |

`Booking` gains four nullable columns - `DepartureId`, `TicketBreakdown`,
`Waiver`, `Source` - and `BookingStatus` gains `WeatherCancelled`, appended
last (the enum persists by name, so existing rows are unaffected).
`EquipmentItem` gains a nullable `ExpiryDate` for date-controlled safety gear.

Notable behaviours:
- **Cancel-with-notify** (`POST /api/departures/{id}/cancel-weather`) is one
  action: every booking moves to `WeatherCancelled`, every guest gets a
  `Notification` and a push, the conditions are recorded, and the alternative
  departures come back in the response. It deliberately ignores the guest
  cancellation cutoff - a cutoff cannot make the sea calmer - but the
  follow-up bulk reschedule *does* honour `Tenant.RescheduleCutoffHours`.
- **Weather cancellations are excluded from the sighting success rate.** The
  sea being too rough to leave harbour is not a failure to find whales, and
  counting it as one would make a stormy month read as bad spotting.
  `GET /api/sightings/success-rate` returns the rate and its two counts for
  the KPI card; `GET /api/sightings/analytics` returns the same rate plus
  species frequency and a monthly breakdown. Both count a departure once
  however many sightings it logged.
- **The pre-departure safety checklist gates `AtSea`** as a soft warning:
  only an Admin can override it, not the captain.
- **Refund figures are reported as "at risk", not "refunded".** There is no
  payment gateway in this system, so the value on cancelled bookings is not
  a settled refund total.
