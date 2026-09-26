using System.Text.Json;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// Gym-specific settings, read from ConfigJson the same config-not-code
/// way as RestaurantConfig:
///
/// On a BookingType:
///   { "kind": "access" | "class" | "pt" | "dropIn" }
///   access = a plain gym check-in (the turnstile / front desk), class = a
///   group session with a capacity, pt = personal training, dropIn = a
///   paid day pass or trial. Inferred from the name and MaxParticipants
///   when absent.
///
/// On the tenant's "Memberships" module (TenantModule.ConfigJson):
///   { "facilityCapacity": 120, "monthlyRevenueTarget": 900000,
///     "yearlyRevenueTarget": 10800000, "openHoursPerDay": 15,
///     "maintenanceEveryUses": 200 }
public static class GymConfig
{
    public const string Access = "access";
    public const string Class = "class";
    public const string PersonalTraining = "pt";
    public const string DropIn = "dropIn";

    public const string MembershipsModule = "Memberships";
    public const int DefaultOpenHoursPerDay = 15;
    public const int DefaultMaintenanceEveryUses = 200;

    public sealed record Targets(int? FacilityCapacity, decimal? MonthlyRevenueTarget, decimal? YearlyRevenueTarget, int OpenHoursPerDay, int MaintenanceEveryUses);

    public static string KindOf(BookingType type)
    {
        var configured = ReadString(type.ConfigJson, "kind")?.Trim().ToLowerInvariant();
        switch (configured)
        {
            case "access": return Access;
            case "class": return Class;
            case "pt" or "personaltraining" or "personal-training": return PersonalTraining;
            case "dropin" or "drop-in" or "daypass" or "trial": return DropIn;
        }
        var n = type.Name.ToLowerInvariant();
        if (n.Contains("trial") || n.Contains("drop-in") || n.Contains("drop in") || n.Contains("day pass") || n.Contains("guest pass")) return DropIn;
        if (n.Contains("access") || n.Contains("open gym") || n.Contains("check-in") || n.Contains("check in") || n.Contains("gym visit")) return Access;
        if ((type.MaxParticipants ?? 1) > 1 || n.Contains("class") || n.Contains("yoga") || n.Contains("spin") || n.Contains("hiit") || n.Contains("zumba") || n.Contains("pilates") || n.Contains("bootcamp")) return Class;
        return PersonalTraining;
    }

    public static Targets TargetsOf(string? moduleConfigJson)
    {
        int? capacity = null; decimal? monthly = null; decimal? yearly = null;
        var openHours = DefaultOpenHoursPerDay; var every = DefaultMaintenanceEveryUses;
        if (!string.IsNullOrWhiteSpace(moduleConfigJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(moduleConfigJson);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    capacity = ReadInt(doc.RootElement, "facilityCapacity");
                    monthly = ReadDecimal(doc.RootElement, "monthlyRevenueTarget");
                    yearly = ReadDecimal(doc.RootElement, "yearlyRevenueTarget");
                    openHours = ReadInt(doc.RootElement, "openHoursPerDay") is int oh && oh is > 0 and <= 24 ? oh : openHours;
                    every = ReadInt(doc.RootElement, "maintenanceEveryUses") is int me && me > 0 ? me : every;
                }
            }
            catch (JsonException)
            {
                // Malformed config: defaults, never a 500 on the dashboard.
            }
        }
        return new Targets(capacity, monthly, yearly, openHours, every);
    }

    private static int? ReadInt(JsonElement root, string name) =>
        root.TryGetProperty(name, out var el) && el.ValueKind == JsonValueKind.Number && el.TryGetInt32(out var v) ? v : null;

    private static decimal? ReadDecimal(JsonElement root, string name) =>
        root.TryGetProperty(name, out var el) && el.ValueKind == JsonValueKind.Number && el.TryGetDecimal(out var v) ? v : null;

    private static string? ReadString(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty(property, out var el)
                && el.ValueKind == JsonValueKind.String)
            {
                return el.GetString();
            }
        }
        catch (JsonException)
        {
        }
        return null;
    }
}
