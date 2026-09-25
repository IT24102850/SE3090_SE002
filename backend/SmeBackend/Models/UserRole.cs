namespace SmeBackend.Models;

public enum UserRole
{
    Admin,
    Manager,
    Staff,
    Customer,
    // The platform owner. Not a tenant role: it never appears in the
    // Admin/Manager/Staff policies, cannot sign in through the ordinary
    // login, and is only honoured by the PlatformOwner policy (password +
    // TOTP + a live server-side session). Appended last because Role is
    // stored as an int.
    SuperAdmin
}
