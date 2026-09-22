using System.Globalization;
using System.Text.Json;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// School-specific settings, read from ConfigJson the same config-not-code
/// way as the restaurant and gym helpers.
///
/// On a BookingType (a subject / course / assessment):
///   { "kind": "lesson" | "tutoring" | "exam" | "assignment",
///     "subject": "Mathematics", "grade": "Grade 10", "weight": 0.4 }
///   kind is inferred from the name when absent; weight is the share of
///   the final mark an exam / assignment carries (default 1).
///
/// On a lesson booking's FormData (one per student per session):
///   { "attendance": "present" | "late" | "absent" | "excused",
///     "points": 1, "note": "Helped a classmate" }
///
/// On an exam / assignment booking's FormData:
///   { "score": 78, "maxScore": 100, "submittedAt": "2026-09-10T08:00Z",
///     "feedback": "Show working on Q4", "dueAt": "2026-09-12T15:00Z" }
///
/// On the tenant's "Scheduling" module (TenantModule.ConfigJson):
///   { "terms": [{ "name": "Term 3", "from": "2026-09-01", "to": "2026-11-27" }],
///     "holidays": [{ "date": "2026-10-06", "name": "Vap Poya" }] }
///
/// On the tenant's "Attendance" module:
///   { "atRiskAttendancePercent": 75, "atRiskGradePercent": 50,
///     "lateAfterMinutes": 10, "gradeScale": [{ "grade": "A", "min": 75 }, ...] }
public static class SchoolConfig
{
    public const string Lesson = "lesson";
    public const string Tutoring = "tutoring";
    public const string Exam = "exam";
    public const string Assignment = "assignment";

    public const string SchedulingModule = "Scheduling";
    public const string AttendanceModule = "Attendance";

    public sealed record Term(string Name, DateTime From, DateTime To);
    public sealed record Holiday(DateTime Date, string Name);
    public sealed record Calendar(List<Term> Terms, List<Holiday> Holidays);
    public sealed record GradeBand(string Grade, double Min);
    public sealed record Thresholds(double AtRiskAttendancePercent, double AtRiskGradePercent, int LateAfterMinutes, List<GradeBand> Scale);
    public sealed record Attendance(string? Mark, int Points, string? Note);
    public sealed record Assessment(double? Score, double MaxScore, DateTime? SubmittedAt, DateTime? DueAt, string? Feedback);

    private static readonly List<GradeBand> DefaultScale = new()
    {
        new("A", 75), new("B", 65), new("C", 55), new("S", 40), new("F", 0),
    };

    public static string KindOf(BookingType type)
    {
        var configured = ReadString(type.ConfigJson, "kind")?.Trim().ToLowerInvariant();
        switch (configured)
        {
            case "lesson" or "class": return Lesson;
            case "tutoring" or "tuition" or "1-on-1": return Tutoring;
            case "exam" or "test" or "quiz": return Exam;
            case "assignment" or "homework": return Assignment;
        }
        var n = type.Name.ToLowerInvariant();
        if (n.Contains("exam") || n.Contains("test") || n.Contains("quiz")) return Exam;
        if (n.Contains("assignment") || n.Contains("homework")) return Assignment;
        if (n.Contains("1-on-1") || n.Contains("one-to-one") || n.Contains("tutor")) return Tutoring;
        return Lesson;
    }

    public static string? SubjectOf(BookingType type) => ReadString(type.ConfigJson, "subject") ?? type.Name;
    public static string? GradeOf(BookingType type) => ReadString(type.ConfigJson, "grade");

    public static double WeightOf(BookingType type)
    {
        var w = ReadNumber(type.ConfigJson, "weight");
        return w is > 0 ? w.Value : 1;
    }

    public static Attendance AttendanceOf(string? formData)
    {
        var mark = ReadString(formData, "attendance")?.Trim().ToLowerInvariant();
        if (mark is not ("present" or "late" or "absent" or "excused")) mark = null;
        var points = ReadNumber(formData, "points");
        return new Attendance(mark, points.HasValue ? (int)Math.Round(points.Value) : 0, ReadString(formData, "note"));
    }

    public static Assessment AssessmentOf(string? formData)
    {
        var max = ReadNumber(formData, "maxScore");
        return new Assessment(
            ReadNumber(formData, "score"),
            max is > 0 ? max.Value : 100,
            ReadDate(formData, "submittedAt"),
            ReadDate(formData, "dueAt"),
            ReadString(formData, "feedback"));
    }

    public static Calendar CalendarOf(string? moduleConfigJson)
    {
        var terms = new List<Term>();
        var holidays = new List<Holiday>();
        if (string.IsNullOrWhiteSpace(moduleConfigJson)) return new Calendar(terms, holidays);
        try
        {
            using var doc = JsonDocument.Parse(moduleConfigJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return new Calendar(terms, holidays);
            if (doc.RootElement.TryGetProperty("terms", out var t) && t.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in t.EnumerateArray())
                {
                    var name = Str(el, "name"); var from = Date(el, "from"); var to = Date(el, "to");
                    if (name != null && from != null && to != null) terms.Add(new Term(name, from.Value, to.Value));
                }
            }
            if (doc.RootElement.TryGetProperty("holidays", out var h) && h.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in h.EnumerateArray())
                {
                    var name = Str(el, "name"); var date = Date(el, "date");
                    if (date != null) holidays.Add(new Holiday(date.Value, name ?? "Holiday"));
                }
            }
        }
        catch (JsonException)
        {
        }
        return new Calendar(terms.OrderBy(x => x.From).ToList(), holidays.OrderBy(x => x.Date).ToList());
    }

    public static Thresholds ThresholdsOf(string? moduleConfigJson)
    {
        double attendance = 75, grade = 50; var late = 10; var scale = DefaultScale;
        if (!string.IsNullOrWhiteSpace(moduleConfigJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(moduleConfigJson);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    var root = doc.RootElement;
                    if (root.TryGetProperty("atRiskAttendancePercent", out var a) && a.ValueKind == JsonValueKind.Number) attendance = a.GetDouble();
                    if (root.TryGetProperty("atRiskGradePercent", out var g) && g.ValueKind == JsonValueKind.Number) grade = g.GetDouble();
                    if (root.TryGetProperty("lateAfterMinutes", out var l) && l.ValueKind == JsonValueKind.Number && l.TryGetInt32(out var lm) && lm >= 0) late = lm;
                    if (root.TryGetProperty("gradeScale", out var s) && s.ValueKind == JsonValueKind.Array)
                    {
                        var bands = new List<GradeBand>();
                        foreach (var el in s.EnumerateArray())
                        {
                            var label = Str(el, "grade");
                            if (label != null && el.TryGetProperty("min", out var m) && m.ValueKind == JsonValueKind.Number) bands.Add(new GradeBand(label, m.GetDouble()));
                        }
                        if (bands.Count > 0) scale = bands.OrderByDescending(b => b.Min).ToList();
                    }
                }
            }
            catch (JsonException)
            {
            }
        }
        return new Thresholds(attendance, grade, late, scale);
    }

    public static string LetterOf(double percent, IEnumerable<GradeBand> scale) =>
        scale.OrderByDescending(b => b.Min).FirstOrDefault(b => percent >= b.Min)?.Grade ?? scale.Last().Grade;

    private static string? Str(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static DateTime? Date(JsonElement el, string name)
    {
        var s = Str(el, name);
        return s != null && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var d) ? d : null;
    }

    private static string? ReadString(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return Str(doc.RootElement, property);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static double? ReadNumber(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.ValueKind == JsonValueKind.Object && doc.RootElement.TryGetProperty(property, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static DateTime? ReadDate(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return Date(doc.RootElement, property);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// Merges a few keys into a jsonb FormData string without disturbing
    /// whatever else a custom form put there.
    public static string Merge(string? formData, IDictionary<string, object?> values)
    {
        var map = new Dictionary<string, object?>();
        if (!string.IsNullOrWhiteSpace(formData))
        {
            try
            {
                using var doc = JsonDocument.Parse(formData);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                    foreach (var p in doc.RootElement.EnumerateObject()) map[p.Name] = JsonSerializer.Deserialize<object>(p.Value.GetRawText());
            }
            catch (JsonException)
            {
            }
        }
        foreach (var (k, v) in values)
        {
            if (v == null) map.Remove(k); else map[k] = v;
        }
        return JsonSerializer.Serialize(map);
    }
}
