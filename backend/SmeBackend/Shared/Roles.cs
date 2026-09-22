namespace SmeBackend.Shared;

public static class Roles
{
    public const string Admin = "Admin";
    public const string Manager = "Manager";
    public const string Staff = "Staff";
    public const string Customer = "Customer";
    // Platform owner - see Models/UserRole.cs. Deliberately not in AllRoles:
    // that list is what tenant admins may hand out.
    public const string SuperAdmin = "SuperAdmin";

    public static readonly string[] AllRoles = { Admin, Manager, Staff, Customer };
}
