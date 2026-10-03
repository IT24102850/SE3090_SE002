# Hasiru - AI Usage Log

## 2026-08-01
- **Tool:** GitHub Copilot (GPT-5.4 mini)
- **Task:** Created the AI usage log and initialized the daily tracking format
- **What it produced:** A markdown log template ready for ongoing daily entries
- **What was changed:** Added the log file under `docs/` with a first dated entry
- **Verification:** Confirmed the file did not exist before creation and added the requested markdown structure

## 2026-08-03
- **Tool:** GitHub Copilot
- **Task:** Bootstrap the ASP.NET Core Web API project and define the solution structure.
- **What it produced:** Suggested `dotnet new webapi` commands and a standard `.sln` / `.csproj` folder layout.
- **What was changed:** Manually ran the commands, created the solution file, and organized the initial project folders (`Models`, `Data`, `Controllers`, `Services`). Deleted the old Node.js project files.
- **Verification:** The new solution built successfully with `dotnet build`.

## 2026-08-04
- **Tool:** Gemini Code Assist
- **Task:** Configure Entity Framework Core to connect to the provisioned Supabase PostgreSQL database.
- **What it produced:** Code snippets for registering `AppDbContext` in `Program.cs` with `UseNpgsql` and an example of structuring the connection string in `appsettings.json`.
- **What was changed:** Manually provisioned the database on Supabase. Adapted the generated code to use the actual connection string, configuring it via .NET user secrets for security.
- **Verification:** The application successfully connected to the database on startup without errors.

## 2026-08-05
- **Tool:** ChatGPT (GPT-4)
- **Task:** Design the initial EF Core models for core shared entities (`Tenant`, `Branch`, `User`, `AgentWorkflow`).
- **What it produced:** C# class definitions for the entities with basic properties and navigation properties.
- **What was changed:** Refined the generated classes, added data annotations, and configured fluent API relationships in `AppDbContext.OnModelCreating` to define foreign keys, cascade deletes, and indexes as per the ADRs.
- **Verification:** The project compiled successfully with the new entity classes and `AppDbContext` configurations.

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

## 2026-08-07
- **Tool:** Gemini Code Assist
- **Task:** Implement JWT authentication with access/refresh tokens and password hashing.
- **What it produced:** Generated `JwtService` for token creation, `AuthController` with register/login/refresh endpoints, `RefreshToken` entity, and related DTOs. Included BCrypt.Net for password hashing.
- **What was changed:** Integrated the generated code. Registered `JwtService` and JWT authentication middleware in `Program.cs`. Added `DbSet<RefreshToken>` to `AppDbContext`. Added JWT configuration to `appsettings.json`.
- **Verification:** Ran `dotnet ef migrations add AddAuthAndRefreshTokens` and `dotnet ef database update` to apply schema changes. Tested the `/api/auth/register` and `/api/auth/login` endpoints successfully using the Swagger UI.

> The entries below were reconstructed from Hasiru-authored Git history. The repository does not preserve the AI tool used for each commit, so the tool is marked as unknown instead of being guessed.

## 2026-08-10
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Merge the booking-engine work into the shared development line.
- **What it produced:** A fast-forwarded integration of the booking-engine branch.
- **What was changed:** Merged pull request #11 into `dev`.
- **Verification:** Commit `a684f61` is present in the authored history.

## 2026-09-08
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Improve the web application navigation and dashboard visual system.
- **What it produced:** A grouped sidebar, dashboard hero, and tokenised theming.
- **What was changed:** Updated the frontend UI in commit `a647129`.
- **Verification:** Commit `a647129` is present in the authored history.

## 2026-09-10
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Add business-specific dashboard and mobile quick-action improvements.
- **What it produced:** A whale-watching tenant dashboard, photo-backed mobile quick actions, an updated login layout, and rerunnable seed support.
- **What was changed:** Updated dashboard, mobile, and seed-related code in commits `6a4c903` and `f19ca6e`.
- **Verification:** Both commits are present in the authored history.

## 2026-09-13
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Integrate inventory analytics and connect the deployed frontend to the backend.
- **What it produced:** Inventory analytics integration and Vercel-to-Render deployment wiring, alongside web UI updates.
- **What was changed:** Merged inventory analytics, updated deployment configuration, and changed the web UI in commits `8b260bf`, `6792aaa`, and `36b022b`.
- **Verification:** All three commits are present in the authored history.

## 2026-09-14
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Continue application updates.
- **What it produced:** The changes recorded in the `update` commit.
- **What was changed:** Updated the repository in commit `e186120`.
- **Verification:** Commit `e186120` is present in the authored history.

## 2026-09-16
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Align the admin console with the product branding and integrate the updated development branch.
- **What it produced:** A blue logo-based admin-console palette and the merged branch changes.
- **What was changed:** Updated the admin UI and merged `hasaranga/updated-dev` in commits `c0e4f7e` and `038e7aa`.
- **Verification:** Both commits are present in the authored history.

## 2026-09-17
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Improve authentication, booking embeds, mobile compatibility, dashboards, and operations UI.
- **What it produced:** Password-change and correct-account login behavior, staff inventory claims, Flutter 3.32 compatibility, a booking widget, robust API-base resolution, subtype-aware embed pricing, a working departure horizon picker, profile-photo display, and an operations-focused Reservations page.
- **What was changed:** Updated backend authentication, frontend booking and dashboard flows, mobile UI, and embedded booking behavior across commits `d155cc1`, `37be669`, `fb86812`, `9b2bf20`, `ee429c0`, `684cd36`, `dd18515`, `add4641`, `59994f9`, `6232047`, and `aa17984`.
- **Verification:** All listed commits are present in the authored history.

## 2026-09-19
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Refine sign-up presentation and sidebar layout.
- **What it produced:** A sign-up page positioned between sign-in and landing content, and a viewport-pinned sidebar.
- **What was changed:** Updated the frontend UI in commits `5e5e34e` and `889424a`.
- **Verification:** Both commits are present in the authored history.

## 2026-09-23
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Deliver business-type operations dashboards, the customer web app, and the platform console, then integrate the billing-engine branch.
- **What it produced:** The related web application surfaces and the billing-engine branch merge.
- **What was changed:** Added the feature set in commit `a497811` and merged pull request #15 in `b670e86`.
- **Verification:** Both commits are present in the authored history.

## 2026-09-27
- **Tool:** Unknown (reconstructed from Git history)
- **Task:** Integrate the latest development changes.
- **What it produced:** The merge represented by pull request #20.
- **What was changed:** Merged `IT24102850/dev` in commit `8a7fcd5`.
- **Verification:** `8a7fcd5` is the current latest commit in the repository as of 2026-09-27.
