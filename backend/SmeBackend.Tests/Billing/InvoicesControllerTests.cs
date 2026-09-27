using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Moq;
using SmeBackend.Controllers;
using SmeBackend.DTOs;
using SmeBackend.Services;
using SmeBackend.Services.Billing;

namespace SmeBackend.Tests.Billing;

/// InvoicesController with its services mocked (xUnit + Moq): checks the
/// controller's own job - who the caller is, and how a service outcome
/// becomes an HTTP response - without touching a database.
public class InvoicesControllerTests
{
    private readonly Mock<IBillingService> _billing = new();
    private readonly Mock<IPaymentCheckoutService> _checkout = new();
    private readonly Mock<IBillingAgentService> _agent = new();
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _userId = Guid.NewGuid();

    private InvoicesController Controller(string role = "Staff", bool withTenant = true)
    {
        var controller = new InvoicesController(_billing.Object, _checkout.Object, _agent.Object);
        if (withTenant) TestHelpers.SetUser(controller, _userId, _tenantId, role);
        else controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private InvoiceResponse SampleInvoice(Guid? id = null) => new(
        id ?? Guid.NewGuid(), _tenantId, Guid.NewGuid(), null, "INV-1", 100m, 0m, 0m, 100m, "Issued",
        DateTime.UtcNow.AddDays(7), "LKR", DateTime.UtcNow, Array.Empty<InvoiceItemResponse>(), Array.Empty<PaymentResponse>());

    private static int? StatusOf(IConvertToActionResult result) => result.Convert() switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => null,
    };

    [Fact]
    public async Task GetInvoices_WithoutATenantClaim_Is401()
    {
        var result = await Controller(withTenant: false).GetInvoices();
        Assert.IsType<UnauthorizedObjectResult>(result.Result);
        _billing.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task GetInvoices_ForAnotherTenant_Is403()
    {
        var result = await Controller().GetInvoices(tenantId: Guid.NewGuid());
        Assert.Equal(403, StatusOf(result));
        _billing.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task GetInvoices_PassesTheCallerAndFiltersToTheService()
    {
        var from = new DateTime(2026, 9, 1);
        _billing.Setup(b => b.GetInvoicesAsync(It.IsAny<BillingActor>(), It.IsAny<InvoiceQuery>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new InvoiceListResponse(Array.Empty<InvoiceResponse>(), 2, 10, 0, 0));

        var result = await Controller("Customer").GetInvoices(tenantId: _tenantId, status: "Paid", from: from, page: 2, pageSize: 10);

        Assert.IsType<OkObjectResult>(result.Result);
        _billing.Verify(b => b.GetInvoicesAsync(
            It.Is<BillingActor>(a => a.TenantId == _tenantId && a.UserId == _userId && a.IsCustomer),
            It.Is<InvoiceQuery>(q => q.Status == "Paid" && q.From == from && q.Page == 2 && q.PageSize == 10),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetMyInvoices_AlwaysScopesToTheCaller_EvenForStaff()
    {
        _billing.Setup(b => b.GetInvoicesAsync(It.IsAny<BillingActor>(), It.IsAny<InvoiceQuery>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new InvoiceListResponse(Array.Empty<InvoiceResponse>(), 1, 50, 0, 0));

        await Controller("Manager").GetMyInvoices();

        _billing.Verify(b => b.GetInvoicesAsync(It.Is<BillingActor>(a => a.IsCustomer && a.UserId == _userId),
            It.IsAny<InvoiceQuery>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetInvoice_NotFound_Is404()
    {
        _billing.Setup(b => b.GetInvoiceAsync(It.IsAny<BillingActor>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<InvoiceResponse>.NotFound("Invoice not found."));
        Assert.Equal(404, StatusOf(await Controller().GetInvoice(Guid.NewGuid())));
    }

    [Fact]
    public async Task CreateInvoice_Success_Is201WithTheInvoice()
    {
        var invoice = SampleInvoice();
        _billing.Setup(b => b.CreateInvoiceAsync(It.IsAny<BillingActor>(), It.IsAny<CreateInvoiceRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<InvoiceResponse>.Created(invoice));

        var result = await Controller().CreateInvoice(BillingTestFixture.InvoiceRequest(Guid.NewGuid()));

        var created = Assert.IsType<ObjectResult>(result.Result);
        Assert.Equal(201, created.StatusCode);
        Assert.Same(invoice, created.Value);
    }

    [Fact]
    public async Task CreateInvoice_InvalidModel_Is400WithoutCallingTheService()
    {
        var controller = Controller();
        controller.ModelState.AddModelError("Items", "At least one invoice item is required.");

        var result = await controller.CreateInvoice(BillingTestFixture.InvoiceRequest(Guid.NewGuid()));

        Assert.IsType<BadRequestObjectResult>(result.Result);
        _billing.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task CreateInvoice_ServiceRejection_Is400WithTheMessage()
    {
        _billing.Setup(b => b.CreateInvoiceAsync(It.IsAny<BillingActor>(), It.IsAny<CreateInvoiceRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<InvoiceResponse>.BadRequest("Customer not found in this business."));

        var result = await Controller().CreateInvoice(BillingTestFixture.InvoiceRequest(Guid.NewGuid()));

        var bad = Assert.IsType<ObjectResult>(result.Result);
        Assert.Equal(400, bad.StatusCode);
        Assert.Contains("Customer not found", bad.Value!.ToString());
    }

    [Fact]
    public async Task Adjust_NeedingApproval_Is202()
    {
        var pending = new AdjustInvoiceResult(false, true, Guid.NewGuid(), SampleInvoice(), "sent for approval");
        _billing.Setup(b => b.AdjustInvoiceAsync(It.IsAny<BillingActor>(), It.IsAny<Guid>(), It.IsAny<AdjustInvoiceRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<AdjustInvoiceResult>.Accepted(pending));

        var result = await Controller().AdjustInvoice(Guid.NewGuid(), new AdjustInvoiceRequest(500m, null, "Goodwill"));

        Assert.Equal(202, StatusOf(result));
    }

    [Fact]
    public async Task Pay_Success_ReturnsPaymentAndInvoice()
    {
        var invoice = SampleInvoice() with { Status = "Paid" };
        var payment = new PaymentResponse(Guid.NewGuid(), invoice.Id, 100m, "Cash", null, null, DateTime.UtcNow, DateTime.UtcNow);
        _billing.Setup(b => b.PayInvoiceAsync(It.IsAny<BillingActor>(), invoice.Id, It.IsAny<PayInvoiceRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<(PaymentResponse, InvoiceResponse)>.Ok((payment, invoice)));

        var result = await Controller().PayInvoice(invoice.Id, new PayInvoiceRequest(100m, "Cash"));

        var ok = Assert.IsType<ObjectResult>(result);
        Assert.Equal(200, ok.StatusCode);
        Assert.Contains("Payment recorded", ok.Value!.ToString());
    }

    [Fact]
    public async Task Checkout_DefaultsTheRequest_AndReturns201()
    {
        var session = new CheckoutResponse(Guid.NewGuid(), Guid.NewGuid(), "Manual", "Pending", 100m, "LKR", null, null, null, "SIM-1", true);
        _checkout.Setup(c => c.StartCheckoutAsync(It.IsAny<BillingActor>(), It.IsAny<Guid>(), It.IsAny<CheckoutRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<CheckoutResponse>.Created(session));

        var result = await Controller("Customer").Checkout(session.InvoiceId, null);

        Assert.Equal(201, StatusOf(result));
        _checkout.Verify(c => c.StartCheckoutAsync(It.IsAny<BillingActor>(), session.InvoiceId,
            It.Is<CheckoutRequest>(r => r.Method == "Card" && r.Provider == null), It.IsAny<CancellationToken>()));
    }

    [Fact]
    public async Task Checkout_ProviderFailure_Is502()
    {
        _checkout.Setup(c => c.StartCheckoutAsync(It.IsAny<BillingActor>(), It.IsAny<Guid>(), It.IsAny<CheckoutRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<CheckoutResponse>.BadGateway("Stripe could not start the payment"));
        Assert.Equal(502, StatusOf(await Controller("Customer").Checkout(Guid.NewGuid(), new CheckoutRequest("Stripe"))));
    }

    [Fact]
    public async Task ReceiptPdf_IsServedAsAFile()
    {
        var bytes = new byte[] { 0x25, 0x50, 0x44, 0x46 };
        _billing.Setup(b => b.GetReceiptPdfAsync(It.IsAny<BillingActor>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(BillingResult<(byte[], string)>.Ok((bytes, "REC-INV-1.pdf")));

        var result = await Controller("Customer").GetReceiptPdf(Guid.NewGuid());

        var file = Assert.IsType<FileContentResult>(result);
        Assert.Equal("application/pdf", file.ContentType);
        Assert.Equal("REC-INV-1.pdf", file.FileDownloadName);
    }

    [Fact]
    public void ValidateDraft_DelegatesToTheAgent()
    {
        var draft = BillingTestFixture.InvoiceRequest(Guid.NewGuid(), unitPrice: 10m, discount: 5m);
        _agent.Setup(a => a.ValidateInvoiceDraft(draft, null))
            .Returns(new InvoiceValidationResult(true, true, 10m, 50m, 0m, 5m, new[] { new InvoiceValidationIssue("excessive_discount", "warning", "…") }));

        var result = Controller().ValidateDraft(draft);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.True(((InvoiceValidationResult)ok.Value!).RequiresReview);
    }
}
