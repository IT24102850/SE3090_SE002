namespace SmeBackend.Models;

public static class InvoiceStatuses
{
    public const string Draft = "Draft";
    public const string Issued = "Issued";
    public const string PartiallyPaid = "PartiallyPaid";
    public const string Paid = "Paid";
    public const string Overdue = "Overdue";
    public const string Cancelled = "Cancelled";

    /// The status an invoice's balance implies. Cancelled and Draft are
    /// deliberate states and are never overwritten by a payment change.
    public static string FromBalance(decimal finalAmount, decimal paid, string current)
    {
        if (current is Cancelled or Draft) return current;
        if (paid >= finalAmount) return Paid;
        if (paid > 0) return PartiallyPaid;
        return current == Overdue ? Overdue : Issued;
    }

    public static bool IsOpen(string status) => status is Issued or PartiallyPaid or Overdue;
}

/// Subscription.Status values (the column is 20 chars wide).
public static class SubscriptionStatuses
{
    public const string Active = "Active";
    public const string Frozen = "Frozen";
    /// A cancellation with a refund, waiting for an Admin.
    public const string PendingCancel = "PendingCancel";
    public const string Cancelled = "Cancelled";
    public const string Expired = "Expired";
}
