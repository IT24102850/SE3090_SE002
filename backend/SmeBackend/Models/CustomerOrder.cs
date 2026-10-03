namespace SmeBackend.Models;

public class CustomerOrder : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid CustomerId { get; set; }
    public Guid BranchId { get; set; }
    public string Number { get; set; } = string.Empty;
    public string Status { get; set; } = "Pending";
    public string PaymentStatus { get; set; } = "DueOnFulfillment";
    public string FulfillmentMethod { get; set; } = "Pickup";
    public string? DeliveryAddress { get; set; }
    public decimal? DeliveryLatitude { get; set; }
    public decimal? DeliveryLongitude { get; set; }
    public string? Notes { get; set; }
    public decimal Total { get; set; }
    public IList<CustomerOrderItem> Items { get; set; } = new List<CustomerOrderItem>();
    public IList<CustomerOrderStatusUpdate> StatusUpdates { get; set; } = new List<CustomerOrderStatusUpdate>();
}
