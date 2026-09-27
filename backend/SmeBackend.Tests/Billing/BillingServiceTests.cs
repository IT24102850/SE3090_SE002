using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Tests.Billing;

/// Payment processing logic, subscription calculations and the approval
/// gates, against the real BillingService over an in-memory database.
public class BillingServiceTests
{
    // ------------------------------------------------------------------
    // Invoices
    // ------------------------------------------------------------------

    [Fact]
    public async Task CreateInvoice_CalculatesTotalsServerSide_FromPercentages()
    {
        var f = new BillingTestFixture();

        var result = await f.Billing.CreateInvoiceAsync(f.StaffActor,
            BillingTestFixture.InvoiceRequest(f.Customer.Id, unitPrice: 2500m, qty: 2, discountPercent: 10m, taxRatePercent: 8m));

        Assert.Equal(201, result.StatusCode);
        var invoice = result.Value!;
        Assert.Equal(5000m, invoice.TotalAmount);
        Assert.Equal(500m, invoice.Discount);
        Assert.Equal(360m, invoice.Tax);          // 8% of 4500
        Assert.Equal(4860m, invoice.FinalAmount);
        Assert.Equal("Issued", invoice.Status);
        Assert.Equal("Nimal Perera", invoice.CustomerName);
        Assert.StartsWith("INV-", invoice.InvoiceNumber);
    }

    [Fact]
    public async Task CreateInvoice_ForACustomerOfAnotherBusiness_IsRejected()
    {
        var f = new BillingTestFixture();
        var result = await f.Billing.CreateInvoiceAsync(f.StaffActor, BillingTestFixture.InvoiceRequest(Guid.NewGuid()));
        Assert.Equal(400, result.StatusCode);
        Assert.Contains("Customer not found", result.Error);
    }

    [Fact]
    public async Task CreateInvoice_WithExcessiveDiscount_IsIssuedButFlaggedForReview()
    {
        var f = new BillingTestFixture();

        var result = await f.Billing.CreateInvoiceAsync(f.StaffActor, BillingTestFixture.InvoiceRequest(f.Customer.Id, unitPrice: 10m, discount: 5m));

        Assert.True(result.Success);
        Assert.Contains(result.Value!.ValidationIssues!, i => i.Code == "excessive_discount");
        var flag = await f.Db.AgentWorkflows.SingleAsync();
        Assert.Equal("Pending", flag.ApprovalStatus);
        Assert.Contains("review_invoice", flag.PlanJson);
    }

    [Fact]
    public async Task CreateInvoice_WithDiscountAboveSubtotal_IsRejected()
    {
        var f = new BillingTestFixture();
        var result = await f.Billing.CreateInvoiceAsync(f.StaffActor, BillingTestFixture.InvoiceRequest(f.Customer.Id, unitPrice: 10m, discount: 15m));
        Assert.Equal(400, result.StatusCode);
        Assert.Empty(f.Db.Invoices);
    }

    [Fact]
    public async Task Customer_OnlySeesTheirOwnInvoices()
    {
        var f = new BillingTestFixture();
        var mine = await f.CreateInvoiceAsync();
        var theirs = await f.CreateInvoiceAsync(customer: f.OtherCustomer);

        var list = await f.Billing.GetInvoicesAsync(f.CustomerActor, new InvoiceQuery(CustomerId: f.OtherCustomer.Id));
        Assert.Equal(mine.Id, Assert.Single(list.Items).Id);

        var peek = await f.Billing.GetInvoiceAsync(f.CustomerActor, theirs.Id);
        Assert.Equal(404, peek.StatusCode);
        var receipt = await f.Billing.GetReceiptAsync(f.CustomerActor, theirs.Id);
        Assert.Equal(404, receipt.StatusCode);
    }

    [Fact]
    public async Task InvoiceList_FiltersByOverdue()
    {
        var f = new BillingTestFixture();
        await f.CreateInvoiceAsync(due: DateTime.UtcNow.AddDays(-5));
        await f.CreateInvoiceAsync(due: DateTime.UtcNow.AddDays(5));

        var overdue = await f.Billing.GetInvoicesAsync(f.StaffActor, new InvoiceQuery(Status: "Overdue"));

        var row = Assert.Single(overdue.Items);
        Assert.True(row.IsOverdue);
        Assert.Equal("Overdue", row.Status);
    }

    // ------------------------------------------------------------------
    // Payments
    // ------------------------------------------------------------------

    [Fact]
    public async Task Pay_PartialThenFull_MovesStatusAndBalance()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 3000m);

        var first = await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(1000m, "Cash"));
        Assert.Equal("PartiallyPaid", first.Value.Invoice.Status);
        Assert.Equal(2000m, first.Value.Invoice.BalanceDue);

        var second = await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(2000m, "Card"));
        Assert.Equal("Paid", second.Value.Invoice.Status);
        Assert.Equal(0m, second.Value.Invoice.BalanceDue);
        Assert.Equal(3000m, second.Value.Invoice.AmountPaid);
    }

    [Fact]
    public async Task Pay_MoreThanTheBalance_IsRejected()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 500m);
        var result = await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(600m, "Cash"));
        Assert.Equal(400, result.StatusCode);
        Assert.Contains("exceeds outstanding balance", result.Error);
    }

    [Fact]
    public async Task SplitPay_RecordsEveryShare()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 4500m);

        var result = await f.Billing.SplitPayInvoiceAsync(f.StaffActor, invoice.Id, new SplitPaymentRequest(new()
        {
            new(1500m, "Cash", "Guest 1"),
            new(1500m, "Card"),
            new(1500m, "Card", "Guest 3"),
        }));

        Assert.Equal("Paid", result.Value!.Status);
        Assert.Equal(3, result.Value.Payments.Count);
        Assert.Contains(result.Value.Payments, p => p.PayerLabel == "Share 2 of 3");
    }

    [Fact]
    public async Task SplitPay_ExceedingTheBalance_RecordsNothing()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);

        var result = await f.Billing.SplitPayInvoiceAsync(f.StaffActor, invoice.Id,
            new SplitPaymentRequest(new() { new(600m, "Cash"), new(600m, "Card") }));

        Assert.Equal(400, result.StatusCode);
        Assert.Empty(f.Db.Payments);
    }

    [Fact]
    public async Task Pay_OnACancelledInvoice_IsRejected()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();
        await f.Billing.CancelInvoiceAsync(f.ManagerActor, invoice.Id, new CancelInvoiceRequest("Duplicate"));

        var result = await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(100m, "Cash"));
        Assert.Contains("cancelled", result.Error);
    }

    [Fact]
    public async Task Cancel_AnInvoiceWithPayments_IsRefused()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();
        await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(100m, "Cash"));

        var result = await f.Billing.CancelInvoiceAsync(f.ManagerActor, invoice.Id, new CancelInvoiceRequest(null));
        Assert.Equal(400, result.StatusCode);
    }

    // ------------------------------------------------------------------
    // Approval gate: invoice adjustment > 100
    // ------------------------------------------------------------------

    [Fact]
    public async Task Adjust_Under100_IsAppliedImmediately()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);

        var result = await f.Billing.AdjustInvoiceAsync(f.StaffActor, invoice.Id, new AdjustInvoiceRequest(50m, null, "Loyalty"));

        Assert.Equal(200, result.StatusCode);
        Assert.True(result.Value!.Applied);
        Assert.Equal(950m, result.Value.Invoice.FinalAmount);
    }

    [Fact]
    public async Task Adjust_Over100ByAManager_WaitsForAnAdmin_ThenApplies()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);

        var request = await f.Billing.AdjustInvoiceAsync(f.ManagerActor, invoice.Id, new AdjustInvoiceRequest(250m, null, "Goodwill"));
        Assert.Equal(202, request.StatusCode);
        Assert.True(request.Value!.RequiresApproval);
        Assert.Equal(1000m, (await f.Db.Invoices.SingleAsync()).FinalAmount);

        var wfId = request.Value.ApprovalWorkflowId!.Value;
        var byManager = await f.Approvals.ApproveAsync(f.TenantId, wfId, f.Manager.Id, "Manager");
        Assert.Equal(403, byManager.StatusCode);

        var byAdmin = await f.Approvals.ApproveAsync(f.TenantId, wfId, f.Admin.Id, "Admin");
        Assert.True(byAdmin.Success, byAdmin.Message);
        Assert.Equal(750m, (await f.Db.Invoices.SingleAsync()).FinalAmount);

        var wf = await f.Db.AgentWorkflows.SingleAsync(w => w.Id == wfId);
        Assert.Equal("Approved", wf.ApprovalStatus);
        Assert.Equal(f.Admin.Id, wf.ApprovedBy);
    }

    [Fact]
    public async Task Adjust_Over100ByAnAdmin_IsAppliedAndAudited()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);

        var result = await f.Billing.AdjustInvoiceAsync(f.AdminActor, invoice.Id, new AdjustInvoiceRequest(300m, null, "Price match"));

        Assert.True(result.Value!.Applied);
        Assert.Equal(700m, result.Value.Invoice.FinalAmount);
        var audit = await f.Db.AgentWorkflows.SingleAsync();
        Assert.Equal("Approved", audit.ApprovalStatus);
        Assert.Equal("Completed", audit.Status);
    }

    [Fact]
    public async Task Adjust_WhileAnotherIsPending_IsAConflict()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);
        await f.Billing.AdjustInvoiceAsync(f.ManagerActor, invoice.Id, new AdjustInvoiceRequest(250m, null, "First"));

        var second = await f.Billing.AdjustInvoiceAsync(f.ManagerActor, invoice.Id, new AdjustInvoiceRequest(10m, null, "Second"));
        Assert.Equal(409, second.StatusCode);
    }

    [Fact]
    public async Task RejectedAdjustment_LeavesTheInvoiceUnchanged()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);
        var request = await f.Billing.AdjustInvoiceAsync(f.ManagerActor, invoice.Id, new AdjustInvoiceRequest(400m, null, "Too generous"));

        var rejected = await f.Approvals.RejectAsync(f.TenantId, request.Value!.ApprovalWorkflowId!.Value, f.Admin.Id, "No");
        Assert.True(rejected.Success);
        Assert.Equal(1000m, (await f.Db.Invoices.SingleAsync()).FinalAmount);

        var again = await f.Approvals.ApproveAsync(f.TenantId, request.Value.ApprovalWorkflowId.Value, f.Admin.Id, "Admin");
        Assert.Equal(409, again.StatusCode);
    }

    // ------------------------------------------------------------------
    // Approval gate: insurance claim > 500
    // ------------------------------------------------------------------

    [Fact]
    public async Task Claim_Over500ApprovedByStaff_GoesToAnAdmin()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2000m);
        var claim = (await f.Billing.CreateInsuranceClaimAsync(f.CustomerActor,
            new CreateInsuranceClaimRequest(invoice.Id, "Ceylinco", "CEY-2026-00417", 800m))).Value!;
        Assert.True(claim.RequiresAdminApproval);

        var byStaff = await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("Approved"));
        Assert.Equal(202, byStaff.StatusCode);
        Assert.Equal("UnderReview", byStaff.Value!.Claim.Status);

        var approved = await f.Approvals.ApproveAsync(f.TenantId, byStaff.Value.ApprovalWorkflowId!.Value, f.Admin.Id, "Admin");
        Assert.True(approved.Success, approved.Message);
        var stored = await f.Db.InsuranceClaims.SingleAsync();
        Assert.Equal("Approved", stored.Status);
        Assert.NotNull(stored.ApprovedAt);
    }

    [Fact]
    public async Task Claim_Under500_CanBeApprovedByStaff()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2000m);
        var claim = (await f.Billing.CreateInsuranceClaimAsync(f.StaffActor,
            new CreateInsuranceClaimRequest(invoice.Id, "Ceylinco", "CEY-2026-00417", 300m))).Value!;

        await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("UnderReview"));
        var approved = await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("Approved"));

        Assert.Equal(200, approved.StatusCode);
        Assert.Equal("Approved", approved.Value!.Claim.Status);
        Assert.NotNull(approved.Value.Claim.ReviewStartedAt);
    }

    [Fact]
    public async Task Claim_LargerThanTheInvoice_IsRejectedAtSubmission()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 400m);
        var result = await f.Billing.CreateInsuranceClaimAsync(f.CustomerActor, new CreateInsuranceClaimRequest(invoice.Id, "AIA", "AIA-1234", 900m));
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task Claim_OnAnotherCustomersInvoice_IsRejected()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(customer: f.OtherCustomer);
        var result = await f.Billing.CreateInsuranceClaimAsync(f.CustomerActor, new CreateInsuranceClaimRequest(invoice.Id, "AIA", "AIA-1234", 100m));
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task Claim_Rejection_NeedsAReason_AndIsFinal()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2000m);
        var claim = (await f.Billing.CreateInsuranceClaimAsync(f.StaffActor, new CreateInsuranceClaimRequest(invoice.Id, "AIA", "AIA-1234", 100m))).Value!;

        var noReason = await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("Rejected"));
        Assert.Equal(400, noReason.StatusCode);

        await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("Rejected", "Not covered"));
        var reopen = await f.Billing.UpdateInsuranceClaimStatusAsync(f.StaffActor, claim.Id, new UpdateInsuranceClaimStatusRequest("UnderReview"));
        Assert.Equal(400, reopen.StatusCode);
    }

    [Fact]
    public async Task ClaimDocuments_AreAppended()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2000m);
        var claim = (await f.Billing.CreateInsuranceClaimAsync(f.CustomerActor, new CreateInsuranceClaimRequest(invoice.Id, "AIA", "AIA-1234", 100m))).Value!;

        await f.Billing.AddClaimDocumentAsync(f.CustomerActor, claim.Id, "https://cdn.example/a.jpg", "card.jpg");
        var result = await f.Billing.AddClaimDocumentAsync(f.CustomerActor, claim.Id, "https://cdn.example/b.pdf", "discharge.pdf");

        Assert.Equal(2, result.Value!.Documents!.Count);
        Assert.Equal("discharge.pdf", result.Value.Documents[1].FileName);
    }

    // ------------------------------------------------------------------
    // Subscriptions
    // ------------------------------------------------------------------

    private static async Task<SubscriptionResponse> CreateSubscriptionAsync(BillingTestFixture f, decimal amount = 6000m,
        string cycle = "Monthly", DateTime? start = null, DateTime? end = null, bool generateInvoice = true, bool autoRenew = true)
    {
        var s = start ?? DateTime.UtcNow.Date.AddDays(-10);
        var result = await f.Billing.CreateSubscriptionAsync(f.StaffActor,
            new CreateSubscriptionRequest(f.Customer.Id, "Standard", amount, cycle, s, end ?? s.AddMonths(1), autoRenew, GenerateInvoice: generateInvoice));
        Assert.True(result.Success, result.Error);
        return result.Value!;
    }

    [Fact]
    public async Task CreateSubscription_WithInvoice_IsPendingUntilPaid()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f);
        Assert.Equal("Pending", sub.PaymentStatus);
        Assert.Equal(sub.EndDate, sub.NextBillingAt);

        var invoice = await f.Db.Invoices.SingleAsync(i => i.SubscriptionId == sub.Id);
        await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(6000m, "Card"));

        var after = await f.Billing.GetSubscriptionAsync(f.CustomerActor, sub.Id);
        Assert.Equal("Paid", after.Value!.PaymentStatus);
        Assert.NotNull(after.Value.LastPaymentAt);
    }

    [Fact]
    public async Task CreateSubscription_RejectsAnUnknownCycle()
    {
        var f = new BillingTestFixture();
        var result = await f.Billing.CreateSubscriptionAsync(f.StaffActor,
            new CreateSubscriptionRequest(f.Customer.Id, "Gold", 100m, "Fortnightly", DateTime.UtcNow, DateTime.UtcNow.AddDays(14)));
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task Cancel_WithoutRefund_IsImmediate()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f, generateInvoice: false);

        var result = await f.Billing.CancelSubscriptionAsync(f.CustomerActor, sub.Id, new CancelSubscriptionRequest("Moving away"));

        Assert.Equal(200, result.StatusCode);
        Assert.Equal("Cancelled", result.Value!.Subscription.Status);
        Assert.False(result.Value.Subscription.AutoRenew);
    }

    [Fact]
    public async Task Cancel_WithRefund_WaitsForAnAdmin_AndRejectionRestoresIt()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f, generateInvoice: false);

        var request = await f.Billing.CancelSubscriptionAsync(f.CustomerActor, sub.Id, new CancelSubscriptionRequest("Injury", 3000m));
        Assert.Equal(202, request.StatusCode);
        Assert.Equal("PendingCancel", request.Value!.Subscription.Status);

        await f.Approvals.RejectAsync(f.TenantId, request.Value.ApprovalWorkflowId!.Value, f.Admin.Id, "Outside refund window");
        var after = await f.Billing.GetSubscriptionAsync(f.StaffActor, sub.Id);
        Assert.Equal("Active", after.Value!.Status);
    }

    [Fact]
    public async Task Cancel_WithRefund_ApprovedByAdmin_CancelsAndRecordsTheRefund()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f);
        var invoice = await f.Db.Invoices.SingleAsync(i => i.SubscriptionId == sub.Id);
        await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(6000m, "Card"));

        var request = await f.Billing.CancelSubscriptionAsync(f.ManagerActor, sub.Id, new CancelSubscriptionRequest("Relocating", 2000m));
        var approved = await f.Approvals.ApproveAsync(f.TenantId, request.Value!.ApprovalWorkflowId!.Value, f.Admin.Id, "Admin");

        Assert.True(approved.Success, approved.Message);
        Assert.Equal("Cancelled", (await f.Db.Subscriptions.SingleAsync()).Status);
        var refund = await f.Db.Payments.SingleAsync(p => p.Status == PaymentStatuses.Refunded);
        Assert.Equal(2000m, refund.Amount);
        Assert.Equal(invoice.Id, refund.InvoiceId);
    }

    [Fact]
    public async Task Cancel_RefundLargerThanWhatWasPaid_IsRejected()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f, amount: 6000m, generateInvoice: false);
        var result = await f.Billing.CancelSubscriptionAsync(f.AdminActor, sub.Id, new CancelSubscriptionRequest(null, 9000m));
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ChangePlan_Upgrade_RaisesAProRataInvoice()
    {
        var f = new BillingTestFixture();
        // A 30-day period with ~15 days left.
        var start = DateTime.UtcNow.AddDays(-15);
        var sub = await CreateSubscriptionAsync(f, amount: 3000m, start: start, end: start.AddDays(30), generateInvoice: false);

        var result = await f.Billing.ChangePlanAsync(f.CustomerActor, sub.Id, new ChangePlanRequest("Premium", 9000m));

        Assert.Equal("Premium", result.Value!.PlanName);
        Assert.Equal(9000m, result.Value.Amount);
        var proration = await f.Db.Invoices.SingleAsync(i => i.SubscriptionId == sub.Id);
        Assert.InRange(proration.FinalAmount, 2900m, 3100m); // (9000 - 3000) * 15/30
    }

    [Fact]
    public async Task ChangePlan_Downgrade_RaisesNoInvoice()
    {
        var f = new BillingTestFixture();
        var sub = await CreateSubscriptionAsync(f, amount: 9000m, generateInvoice: false);
        await f.Billing.ChangePlanAsync(f.CustomerActor, sub.Id, new ChangePlanRequest("Basic", 3000m));
        Assert.Empty(f.Db.Invoices);
    }

    [Fact]
    public async Task RenewalCalendar_ListsRenewalsInRange()
    {
        var f = new BillingTestFixture();
        var soon = DateTime.UtcNow.Date.AddDays(5);
        await CreateSubscriptionAsync(f, start: soon.AddMonths(-1), end: soon, generateInvoice: false);
        await CreateSubscriptionAsync(f, start: soon, end: soon.AddMonths(3), generateInvoice: false);

        var calendar = await f.Billing.GetRenewalCalendarAsync(f.StaffActor, DateTime.UtcNow.Date, DateTime.UtcNow.Date.AddDays(30));

        var entry = Assert.Single(calendar);
        Assert.Equal(soon, entry.RenewalDate);
        Assert.Equal("Nimal Perera", entry.CustomerName);
    }

    // ------------------------------------------------------------------
    // Payment schedules
    // ------------------------------------------------------------------

    [Fact]
    public async Task Schedule_SplitsByPercentage_AndTheLastPartAbsorbsRounding()
    {
        var f = new BillingTestFixture();
        var due = DateTime.UtcNow.Date;

        var result = await f.Billing.CreatePaymentScheduleAsync(f.StaffActor, new CreatePaymentScheduleRequest(
            f.Customer.Id, "Tuition - Term 3", 1000m, new List<PaymentSchedulePart>
            {
                new("Installment 1 of 3", null, 33.33m, due),
                new("Installment 2 of 3", null, 33.33m, due.AddMonths(1)),
                new("Installment 3 of 3", null, 33.34m, due.AddMonths(2)),
            }));

        Assert.Equal(201, result.StatusCode);
        var invoices = result.Value!.Invoices;
        Assert.Equal(3, invoices.Count);
        Assert.Equal(1000m, invoices.Sum(i => i.FinalAmount));
        Assert.All(invoices, i => Assert.Equal(result.Value.ScheduleGroup, i.ScheduleGroup));
    }

    [Fact]
    public async Task Schedule_DepositAndBalance_ThatDoNotAddUp_IsRejected()
    {
        var f = new BillingTestFixture();
        var result = await f.Billing.CreatePaymentScheduleAsync(f.StaffActor, new CreatePaymentScheduleRequest(
            f.Customer.Id, "Safari package", 50000m, new List<PaymentSchedulePart>
            {
                new("Deposit", 10000m, null, DateTime.UtcNow),
                new("Balance", 20000m, null, DateTime.UtcNow.AddDays(30)),
            }));
        Assert.Equal(400, result.StatusCode);
    }

    // ------------------------------------------------------------------
    // Delivery
    // ------------------------------------------------------------------

    [Fact]
    public async Task SendByEmail_AttachesThePdf()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();

        var result = await f.Billing.SendInvoiceAsync(f.StaffActor, invoice.Id, new SendInvoiceRequest("Email"), asReminder: false);

        Assert.True(result.Value!.Delivered);
        f.Messenger.Verify(m => m.SendEmailAsync("nimal@example.com", It.Is<string>(s => s.Contains(invoice.InvoiceNumber)),
            It.IsAny<string>(), It.Is<EmailAttachment?>(a => a != null && a.ContentType == "application/pdf"), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Reminder_ByWhatsApp_UsesTheCustomersPhone()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();

        await f.Billing.SendInvoiceAsync(f.StaffActor, invoice.Id, new SendInvoiceRequest("whatsapp"), asReminder: true);

        f.Messenger.Verify(m => m.SendTextAsync("WhatsApp", "+94771234567", It.Is<string>(s => s.Contains("reminder")), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Reminder_ForAPaidInvoice_IsRefused()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 100m);
        await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(100m, "Cash"));

        var result = await f.Billing.SendInvoiceAsync(f.StaffActor, invoice.Id, new SendInvoiceRequest("Sms"), asReminder: true);
        Assert.Equal(400, result.StatusCode);
        f.Messenger.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ReceiptPdf_IsAValidPdf()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();
        var pdf = await f.Billing.GetReceiptPdfAsync(f.CustomerActor, invoice.Id);

        var text = System.Text.Encoding.Latin1.GetString(pdf.Value.Content);
        Assert.StartsWith("%PDF-1.4", text);
        Assert.EndsWith("%%EOF\n", text);
        Assert.Contains(invoice.InvoiceNumber, text);
        Assert.Contains("Smile Dental", text);
    }
}
