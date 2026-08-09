# Hasiru - AI Usage Log

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
