using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.Billing;

namespace SmeBackend.Tests.Billing;

public class PaymentAndAutomationTests
{
    // ------------------------------------------------------------------
    // Gateway checkout (sandbox) and webhooks
    // ------------------------------------------------------------------

    [Fact]
    public async Task SandboxCheckout_StaysPendingUntilConfirmed_ThenPaysTheInvoice()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2500m);

        var session = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest(Method: "QR"));
        Assert.Equal(201, session.StatusCode);
        Assert.True(session.Value!.Simulated);
        Assert.Equal("Pending", session.Value.Status);
        Assert.Equal("Issued", (await f.Db.Invoices.SingleAsync()).Status);   // a pending payment is not money

        var confirmed = await f.Checkout.ConfirmCheckoutAsync(f.CustomerActor, new ConfirmCheckoutRequest(session.Value.PaymentId));

        Assert.Equal("Succeeded", confirmed.Value.Payment.Status);
        Assert.Equal("Paid", confirmed.Value.Invoice.Status);
        Assert.Contains(f.Db.Notifications, n => n.Type == "PaymentReceived" && n.UserId == f.Customer.Id);
    }

    [Fact]
    public async Task SandboxCheckout_SimulatedFailure_LeavesTheInvoiceUnpaid()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 2500m);
        var session = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest());

        var result = await f.Checkout.ConfirmCheckoutAsync(f.CustomerActor, new ConfirmCheckoutRequest(session.Value!.PaymentId, SimulateFailure: true));

        Assert.Equal("Failed", result.Value.Payment.Status);
        Assert.Equal(2500m, result.Value.Invoice.BalanceDue);
    }

    [Fact]
    public async Task Checkout_OfSomeoneElsesInvoice_IsNotFound()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(customer: f.OtherCustomer);
        var session = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest());
        Assert.Equal(404, session.StatusCode);
    }

    [Fact]
    public async Task Checkout_ForAProviderThatIsNotConfigured_IsRejected()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync();
        var session = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest("Stripe"));
        Assert.Equal(400, session.StatusCode);
        Assert.Contains("not configured", session.Error);
    }

    [Fact]
    public async Task Checkout_ForPartOfTheBalance_IsAllowed_ButNotMoreThanIt()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 50000m);

        var deposit = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest(Amount: 10000m));
        Assert.Equal(10000m, deposit.Value!.Amount);

        var tooMuch = await f.Checkout.StartCheckoutAsync(f.CustomerActor, invoice.Id, new CheckoutRequest(Amount: 60000m));
        Assert.Equal(400, tooMuch.StatusCode);
    }

    [Fact]
    public async Task StripeWebhook_WithAValidSignature_MarksThePaymentSucceeded()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1200m);
        const string secret = "whsec_test_secret";
        await f.Settings.UpsertGatewayAsync(f.TenantId, null,
            new UpsertPaymentGatewayRequest("Stripe", "Stripe", "LKR", true, true, "pk_test_1", "sk_test_1", secret), "https://api.example");

        var entity = await f.Db.Invoices.Include(i => i.Payments).SingleAsync();
        var payment = new Payment { InvoiceId = entity.Id, Amount = 1200m, Method = "Card", Provider = "Stripe", Status = "Pending", TransactionRef = "pi_123" };
        f.Db.Payments.Add(payment);
        await f.Db.SaveChangesAsync();

        var body = JsonSerializer.Serialize(new { type = "payment_intent.succeeded", data = new { @object = new { id = "pi_123" } } });
        var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stripe-Signature"] = $"t={ts},v1={StripePaymentProcessor.ComputeSignature(ts, body, secret)}",
        };

        var result = await f.Checkout.HandleWebhookAsync("stripe", f.TenantId, body, headers);

        Assert.True(result.Success, result.Error);
        Assert.Equal("Succeeded", (await f.Db.Payments.SingleAsync()).Status);
        Assert.Equal("Paid", (await f.Db.Invoices.SingleAsync()).Status);
    }

    [Fact]
    public async Task StripeWebhook_WithABadSignature_IsRejectedAndChangesNothing()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1200m);
        await f.Settings.UpsertGatewayAsync(f.TenantId, null,
            new UpsertPaymentGatewayRequest("Stripe", "Stripe", "LKR", true, true, "pk_test_1", "sk_test_1", "whsec_real"), null);
        f.Db.Payments.Add(new Payment { InvoiceId = invoice.Id, Amount = 1200m, Method = "Card", Provider = "Stripe", Status = "Pending", TransactionRef = "pi_123" });
        await f.Db.SaveChangesAsync();

        var body = """{"type":"payment_intent.succeeded","data":{"object":{"id":"pi_123"}}}""";
        var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var headers = new Dictionary<string, string> { ["Stripe-Signature"] = $"t={ts},v1={StripePaymentProcessor.ComputeSignature(ts, body, "whsec_forged")}" };

        var result = await f.Checkout.HandleWebhookAsync("stripe", f.TenantId, body, headers);

        Assert.Equal(400, result.StatusCode);
        Assert.Equal("Pending", (await f.Db.Payments.SingleAsync()).Status);
    }

    [Fact]
    public void StripeSignature_OutsideTheToleranceWindow_IsRejected()
    {
        const string body = "{}";
        var old = DateTimeOffset.UtcNow.AddMinutes(-10).ToUnixTimeSeconds().ToString();
        var header = $"t={old},v1={StripePaymentProcessor.ComputeSignature(old, body, "s")}";
        Assert.Throws<WebhookSignatureException>(() => StripePaymentProcessor.VerifySignature(body, header, "s", DateTimeOffset.UtcNow));
    }

    [Theory]
    [InlineData(12.34, "LKR", 1234)]
    [InlineData(1500, "JPY", 1500)]
    [InlineData(0.005, "USD", 1)]
    public void StripeAmounts_UseMinorUnits(decimal amount, string currency, long expected) =>
        Assert.Equal(expected, StripePaymentProcessor.ToMinorUnits(amount, currency));

    [Fact]
    public async Task GatewaySecrets_AreEncryptedAndNeverReturned()
    {
        var f = new BillingTestFixture();
        var result = await f.Settings.UpsertGatewayAsync(f.TenantId, null,
            new UpsertPaymentGatewayRequest("Main Stripe", "Stripe", "LKR", true, true, "pk_test_abc", "sk_test_supersecret1234", "whsec_1"),
            "https://api.example");

        var stored = await f.Db.PaymentGateways.SingleAsync();
        Assert.DoesNotContain("supersecret", stored.ApiKeyEncrypted);
        Assert.Equal("••••1234", result.Value!.ApiKeyHint);
        Assert.Equal($"https://api.example/api/payments/webhooks/stripe/{f.TenantId}", result.Value.WebhookUrl);
        Assert.DoesNotContain("supersecret", JsonSerializer.Serialize(result.Value));

        // Updating without a key keeps the stored one.
        var updated = await f.Settings.UpsertGatewayAsync(f.TenantId, stored.Id,
            new UpsertPaymentGatewayRequest("Main Stripe", "Stripe", "LKR", false, true, "pk_test_abc"), null);
        Assert.True(updated.Value!.HasApiKey);
        Assert.False(updated.Value.IsActive);
    }

    [Fact]
    public async Task Gateway_StripeSecretInThePublicKeyField_IsRefused()
    {
        var f = new BillingTestFixture();
        var result = await f.Settings.UpsertGatewayAsync(f.TenantId, null,
            new UpsertPaymentGatewayRequest("Oops", "Stripe", "LKR", true, true, "sk_live_leaked"), null);
        Assert.Equal(400, result.StatusCode);
        Assert.Empty(f.Db.PaymentGateways);
    }

    // ------------------------------------------------------------------
    // Recurring billing engine
    // ------------------------------------------------------------------

    [Fact]
    public async Task Automation_RenewsAutoRenewSubscriptions_AndRaisesTheInvoice()
    {
        var f = new BillingTestFixture();
        var start = new DateTime(2026, 8, 1, 0, 0, 0, DateTimeKind.Utc);
        var sub = (await f.Billing.CreateSubscriptionAsync(f.StaffActor,
            new CreateSubscriptionRequest(f.Customer.Id, "Standard", 6000m, "Monthly", start, start.AddMonths(1), AutoRenew: true))).Value!;

        var now = start.AddMonths(1).AddHours(2);
        var result = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, now);

        Assert.Equal(1, result.Renewed);
        var renewed = await f.Db.Subscriptions.IgnoreQueryFilters().SingleAsync(s => s.Id == sub.Id);
        Assert.Equal(start.AddMonths(2), renewed.EndDate);
        Assert.Equal(start.AddMonths(2), renewed.NextBillingAt);
        Assert.Equal("Pending", renewed.PaymentStatus);
        var invoice = await f.Db.Invoices.Include(i => i.Items).SingleAsync(i => i.SubscriptionId == sub.Id);
        Assert.Equal(6000m, invoice.FinalAmount);
        Assert.Contains("renewal", invoice.Items.Single().Description);

        // Running again straight away does nothing more.
        var again = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, now.AddMinutes(5));
        Assert.Equal(0, again.Renewed);
    }

    [Fact]
    public async Task Automation_ExpiresSubscriptionsThatDoNotRenew()
    {
        var f = new BillingTestFixture();
        var start = DateTime.UtcNow.AddMonths(-2);
        await f.Billing.CreateSubscriptionAsync(f.StaffActor,
            new CreateSubscriptionRequest(f.Customer.Id, "Day pass", 500m, "OneOff", start, start.AddDays(1), AutoRenew: false));

        var result = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, DateTime.UtcNow);

        Assert.Equal(1, result.Expired);
        Assert.Equal("Expired", (await f.Db.Subscriptions.IgnoreQueryFilters().SingleAsync()).Status);
        Assert.Empty(f.Db.Invoices);
    }

    [Fact]
    public async Task Automation_MarksOverdue_AndRemindsAtMostEveryFewDays()
    {
        var f = new BillingTestFixture();
        await f.CreateInvoiceAsync(due: DateTime.UtcNow.AddDays(-3));
        var now = DateTime.UtcNow;

        var first = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, now);
        Assert.Equal(1, first.MarkedOverdue);
        Assert.Equal(1, first.RemindersSent);
        Assert.Equal("Overdue", (await f.Db.Invoices.SingleAsync()).Status);

        var nextHour = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, now.AddHours(1));
        Assert.Equal(0, nextHour.RemindersSent);

        var fourDaysLater = await BillingAutomationService.RunOnceAsync(f.Db, f.Messenger.Object, now.AddDays(4));
        Assert.Equal(1, fourDaysLater.RemindersSent);
    }

    [Theory]
    [InlineData("Weekly", 7)]
    [InlineData("Monthly", 30)]
    [InlineData("Quarterly", 91)]
    [InlineData("Yearly", 365)]
    public void NextPeriodEnd_FollowsTheCycle(string cycle, int days)
    {
        var start = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        Assert.Equal(days, (BillingAutomationService.NextPeriodEnd(start, cycle) - start).Days, tolerance: 1);
    }

    [Theory]
    [InlineData(1200, "Yearly", 100)]
    [InlineData(3000, "Quarterly", 1000)]
    [InlineData(1000, "Monthly", 1000)]
    [InlineData(500, "OneOff", 0)]
    public void MonthlyRecurringValue_NormalisesTheCycle(decimal amount, string cycle, decimal expected) =>
        Assert.Equal(expected, BillingReportService.MonthlyValue(amount, cycle));

    // ------------------------------------------------------------------
    // Reports
    // ------------------------------------------------------------------

    [Fact]
    public async Task OutstandingPayments_BucketsByAge()
    {
        var f = new BillingTestFixture();
        await f.CreateInvoiceAsync(unitPrice: 100m, due: DateTime.UtcNow.AddDays(10));
        await f.CreateInvoiceAsync(unitPrice: 200m, due: DateTime.UtcNow.AddDays(-5));
        await f.CreateInvoiceAsync(unitPrice: 300m, due: DateTime.UtcNow.AddDays(-45));
        var paid = await f.CreateInvoiceAsync(unitPrice: 400m, due: DateTime.UtcNow.AddDays(-45));
        await f.Billing.PayInvoiceAsync(f.StaffActor, paid.Id, new PayInvoiceRequest(400m, "Cash"));

        var all = await f.Reports.GetOutstandingPaymentsAsync(f.TenantId, 0, null);
        Assert.Equal(600m, all.TotalOutstanding);
        Assert.Equal(100m, all.Buckets.Single(b => b.Label == "Not yet due").Amount);
        Assert.Equal(200m, all.Buckets.Single(b => b.Label == "1-30 days").Amount);
        Assert.Equal(300m, all.Buckets.Single(b => b.Label == "31-60 days").Amount);

        var aged = await f.Reports.GetOutstandingPaymentsAsync(f.TenantId, 30, null);
        Assert.Equal(300m, Assert.Single(aged.Items).BalanceDue);
    }

    [Fact]
    public async Task DailyRevenue_CountsPaymentsAndSubtractsRefunds()
    {
        var f = new BillingTestFixture();
        var a = await f.CreateInvoiceAsync(unitPrice: 1000m);
        var b = await f.CreateInvoiceAsync(unitPrice: 500m);
        await f.Billing.PayInvoiceAsync(f.StaffActor, a.Id, new PayInvoiceRequest(1000m, "Card"));
        await f.Billing.PayInvoiceAsync(f.StaffActor, b.Id, new PayInvoiceRequest(500m, "Cash"));
        f.Db.Payments.Add(new Payment { InvoiceId = a.Id, Amount = 200m, Method = "Refund", Status = PaymentStatuses.Refunded, PaidAt = DateTime.UtcNow });
        await f.Db.SaveChangesAsync();

        var report = await f.Reports.GetDailyRevenueAsync(f.TenantId, DateTime.UtcNow, null);

        Assert.Equal(1300m, report.TotalCollected);
        Assert.Equal(2, report.PaymentCount);
        Assert.Equal(1500m, report.TotalInvoiced);
        Assert.Equal(1000m, report.ByMethod.Single(m => m.Label == "Card").Amount);
    }

    [Fact]
    public async Task Dashboard_SummarisesInvoicingCollectionAndRecurringRevenue()
    {
        var f = new BillingTestFixture();
        var invoice = await f.CreateInvoiceAsync(unitPrice: 1000m);
        await f.Billing.PayInvoiceAsync(f.StaffActor, invoice.Id, new PayInvoiceRequest(400m, "Card"));
        await f.Billing.CreateSubscriptionAsync(f.StaffActor, new CreateSubscriptionRequest(
            f.Customer.Id, "Annual", 12000m, "Yearly", DateTime.UtcNow, DateTime.UtcNow.AddYears(1)));

        var d = await f.Reports.GetDashboardAsync(f.TenantId, DateTime.UtcNow.AddDays(-7), DateTime.UtcNow, null);

        Assert.Equal(1000m, d.TotalInvoiced);
        Assert.Equal(400m, d.TotalCollected);
        Assert.Equal(600m, d.TotalOutstanding);
        Assert.Equal(1, d.ActiveSubscriptions);
        Assert.Equal(1000m, d.MonthlyRecurringRevenue);
        Assert.Equal(8, d.RevenueSeries.Count);
    }

    // ------------------------------------------------------------------
    // The agent through its service: persistence + approvals
    // ------------------------------------------------------------------

    [Fact]
    public async Task AgentAnalysis_IsRecorded_AndOpensOneApprovalPerFinding()
    {
        var f = new BillingTestFixture();
        await f.CreateInvoiceAsync(unitPrice: 1000m, discount: 800m);   // 80% off

        var first = await f.Agent.AnalyzeAsync(f.ManagerActor, new BillingAnalysisRequest("anomalies"));

        Assert.True(first.Success, first.Error);
        Assert.Contains(first.Value!.Anomalies, a => a.Type == "excessive_discount");
        var run = await f.Db.AgentWorkflows.SingleAsync(w => w.Id == first.Value.WorkflowId);
        Assert.Equal("Completed", run.Status);
        Assert.Contains("detect_billing_anomalies", run.PlanJson);

        // A second run does not open the same approval twice.
        var second = await f.Agent.AnalyzeAsync(f.ManagerActor, new BillingAnalysisRequest("anomalies"));
        Assert.Equal(first.Value.ApprovalWorkflowIds.OrderBy(x => x), second.Value!.ApprovalWorkflowIds.OrderBy(x => x));

        var monitor = await f.Agent.GetWorkflowsAsync(f.TenantId, "analysis", null, 50);
        Assert.Equal(2, monitor.Count);
    }

    [Fact]
    public async Task AgentAnalysis_OfAnotherTenant_IsForbidden()
    {
        var f = new BillingTestFixture();
        var result = await f.Agent.AnalyzeAsync(f.ManagerActor, new BillingAnalysisRequest("full", TenantId: Guid.NewGuid()));
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task AgentApprovedAdjustment_AppliesTheCorrectedDiscount()
    {
        var f = new BillingTestFixture();
        await f.CreateInvoiceAsync(unitPrice: 1000m, discount: 800m);
        var analysis = await f.Agent.AnalyzeAsync(f.ManagerActor, new BillingAnalysisRequest("anomalies"));
        var adjustment = (await f.Agent.GetWorkflowsAsync(f.TenantId, "approval", "Pending", 50))
            .Single(w => w.ActionType == "adjust_invoice");

        Assert.Contains(adjustment.Id, analysis.Value!.ApprovalWorkflowIds);
        var approved = await f.Approvals.ApproveAsync(f.TenantId, adjustment.Id, f.Admin.Id, "Admin");

        Assert.True(approved.Success, approved.Message);
        var invoice = await f.Db.Invoices.SingleAsync();
        Assert.Equal(300m, invoice.Discount);
        Assert.Equal(700m, invoice.FinalAmount);
    }
}
