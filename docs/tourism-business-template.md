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
`SlotCalculator` model already does well. Two real patterns it doesn't
model natively and would need a larger change to support properly:
- **Per-ticket-type pricing within one booking** (adult vs. child count in
  a single reservation) - currently approximated via `CustomAttributes.pricing`
  as metadata only; the booking flow itself still prices a slot as one
  unit, not "2 adults + 1 child".
- **Multi-resource packages** (e.g. a round-island tour bundling a
  vehicle + multiple hotel nights) - currently would need to be modeled
  as a single `Other`-category resource representing "the package" as a
  simplification, not a true composition of several bookable resources.

Both are flagged here rather than silently worked around, consistent with
the scoped-out limitation already noted for the agentic AI subsystem.
