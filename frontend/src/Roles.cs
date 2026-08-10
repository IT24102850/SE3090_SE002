namespace SmeBackend.Shared
{
    public static class Roles
    {
        public const string Admin = "Admin";
        public const string Manager = "Manager";
        public const string Staff = "Staff";
        public const string Customer = "Customer";

        public static readonly string[] AllRoles = { Admin, Manager, Staff, Customer };
    }
}