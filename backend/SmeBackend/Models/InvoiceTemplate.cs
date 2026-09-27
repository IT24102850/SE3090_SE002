namespace SmeBackend.Models;

/// A tenant's invoice layout, built in the Invoice Designer. LayoutJson is
/// an ordered list of blocks ({ id, type, label, visible, align }) - the
/// designer drags them into order, the receipt PDF and the web preview both
/// render them in that order.
public class InvoiceTemplate : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string Name { get; set; } = string.Empty;
    public bool IsDefault { get; set; }
    public string LayoutJson { get; set; } = "[]";
    public string AccentColor { get; set; } = "#2563eb";
    public string? HeaderText { get; set; }
    public string? FooterText { get; set; }
}
