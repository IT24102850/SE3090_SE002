using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmeBackend.Models;
using SmeBackend.Data;
using System.Linq;
using System;

// Note: This file should be moved to a C# test project, not located in the 'frontend' directory.
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Find and remove the application's DbContext registration.
            var dbContextDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));

            if (dbContextDescriptor != null)
            {
                services.Remove(dbContextDescriptor);
            }

            // Add a new DbContext registration that uses an in-memory database for testing.
            services.AddDbContext<AppDbContext>(options =>
            {
                options.UseInMemoryDatabase("InMemoryDbForTesting");
            });
            
            // The ServiceProvider will be built by the factory.
            // We can seed the database after the services are configured.
            var serviceProvider = services.BuildServiceProvider();
            using (var scope = serviceProvider.CreateScope())
            {
                var scopedServices = scope.ServiceProvider;
                var dbContext = scopedServices.GetRequiredService<AppDbContext>();
                
                // Ensure the database is created.
                dbContext.Database.EnsureCreated();
                
                // Seed the database for testing purposes.
                SeedDatabase(dbContext);
            }
        });
    }

    private void SeedDatabase(AppDbContext context)
    {
        // Prevent re-seeding if data already exists
        if (context.Users.Any())
        {
            return;
        }

        // Create a tenant
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "Lumenis Test Tenant", IsActive = true };
        context.Tenants.Add(tenant);

        // Create users with hashed passwords
        var users = new[]
        {
            new User { Email = "admin@lumenis.com", PasswordHash = BCrypt.Net.BCrypt.HashPassword("Admin@123"), Role = "Admin", TenantId = tenant.Id, IsActive = true, FullName = "Admin User" },
            new User { Email = "manager@lumenis.com", PasswordHash = BCrypt.Net.BCrypt.HashPassword("Manager@123"), Role = "Manager", TenantId = tenant.Id, IsActive = true, FullName = "Manager User" },
            new User { Email = "staff@lumenis.com", PasswordHash = BCrypt.Net.BCrypt.HashPassword("Staff@123"), Role = "Staff", TenantId = tenant.Id, IsActive = true, FullName = "Staff User" },
            new User { Email = "customer@lumenis.com", PasswordHash = BCrypt.Net.BCrypt.HashPassword("Customer@123"), Role = "Customer", TenantId = tenant.Id, IsActive = true, FullName = "Customer User" }
        };

        context.Users.AddRange(users);
        context.SaveChanges();
    }
}