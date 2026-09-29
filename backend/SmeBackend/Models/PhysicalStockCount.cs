namespace SmeBackend.Models;

public class PhysicalStockCount : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid InventoryItemId { get; set; }
    public Guid BranchId { get; set; }
    public string ItemName { get; set; } = string.Empty;
    public string Sku { get; set; } = string.Empty;
    public decimal SystemQuantityAtCount { get; set; }
    public decimal CountedQuantity { get; set; }
    public decimal Variance { get; set; }
    public string Reason { get; set; } = string.Empty;
    public string? ReasonNotes { get; set; }
    public DateTime CountedAt { get; set; }
    public Guid? CountedByUserId { get; set; }
    public string CountedBy { get; set; } = string.Empty;
    public string Reference { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? PhotoUrlsJson { get; set; }
    public string? PhotoUploadKeysJson { get; set; }
    public Guid? ReviewedByUserId { get; set; }
    public string? ReviewedBy { get; set; }
    public DateTime? ReviewedAt { get; set; }
    public string? ReviewNotes { get; set; }
}
