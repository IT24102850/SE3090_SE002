# Hasiru - AI Usage Log

## 2026-08-01
- **Tool:** ChatGPT (GPT-4)
- **Task:** Designed database schema for Bookings, Resources, AvailabilitySlots
- **What it produced:** Draft schema with 10 entities
- **What was changed:** Added TenantId to all tables, added audit fields (CreatedAt, UpdatedAt), added indexes
- **Verification:** Reviewed against SE3090 spec Section 6, normalized to 3NF

## 2026-08-02
- **Tool:** GitHub Copilot (GPT-5.4 mini)
- **Task:** Set up the ASP.NET Core booking backend foundation and aligned EF Core package versions
- **What it produced:** AppDbContext, shared tenant entities, booking entities, migration, and API startup wiring
- **What was changed:** Registered PostgreSQL with `UseNpgsql`, added user secrets for the Supabase connection string, created the initial migration, ran the backend, and pushed the booking branch
- **Verification:** `dotnet build` succeeded, `dotnet ef migrations add InitialCreate` succeeded, backend started on localhost, and the changes were committed and pushed to `feature/booking-engine`
