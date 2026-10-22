using FundManagementAPI.Models;
using FundManagementAPI.Services;
using FundManagementAPI.Repositories;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Data.SqlClient;
using Microsoft.Net.Http.Headers;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;

namespace FundManagementAPI.Controllers;

[ApiController]
[Route("api/cash-advance")]
public sealed class CashAdvanceWorkflowController : ControllerBase
{
    private const decimal PettyCashRequestLimit = 5000m;
    private static readonly FileExtensionContentTypeProvider ContentTypeProvider = new();
    private static readonly JsonSerializerOptions FormJsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly ICashAdvanceRepository _repository;
    private readonly RequestPrintService _requestPrint;
    private readonly IWebHostEnvironment _environment;
    private readonly IDataProtector _printIdProtector;

    public CashAdvanceWorkflowController(
        ICashAdvanceRepository repository,
        RequestPrintService requestPrint,
        IWebHostEnvironment environment,
        IDataProtectionProvider dataProtectionProvider)
    {
        _repository = repository;
        _requestPrint = requestPrint;
        _environment = environment;
        _printIdProtector = dataProtectionProvider.CreateProtector("FundManagementAPI.CashAdvance.DepartmentApprovedPrint.v1");
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<CashAdvanceWorkflowRequestDto>>> GetRequests(
        [FromQuery] int userId,
        [FromQuery] string role,
        [FromQuery] string department,
        CancellationToken cancellationToken)
    {
        if (userId <= 0 || string.IsNullOrWhiteSpace(role) || string.IsNullOrWhiteSpace(department))
        {
            return BadRequest("userId, role, and department are required.");
        }

        var requests = await _repository.GetCashAdvanceRequestsAsync(userId, role, department, cancellationToken);
        return Ok(requests.Select(AddPrintToken).ToArray());
    }

    [HttpGet("receipt-document-number")]
    public async Task<IActionResult> GetReceiptDocumentNumber(CancellationToken cancellationToken)
    {
        var docNo = await _repository.GetReceiptDocumentNumberAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(docNo)) return Problem("Document control did not return a receipt number.");
        return Ok(new { docNo });
    }

    [HttpGet("approval-history")]
    public async Task<ActionResult<IReadOnlyList<CashAdvanceWorkflowRequestDto>>> GetApprovalHistoryRequests(
        [FromQuery] int userId,
        [FromQuery] string role,
        [FromQuery] string department,
        CancellationToken cancellationToken)
    {
        if (userId <= 0 || string.IsNullOrWhiteSpace(role) || string.IsNullOrWhiteSpace(department))
        {
            return BadRequest("userId, role, and department are required.");
        }

        var requests = await _repository.GetApprovalHistoryRequestsAsync(userId, role, department, cancellationToken);
        return Ok(requests.Select(AddPrintToken).ToArray());
    }

    [HttpGet("accounting-report")]
    public async Task<IActionResult> DownloadAccountingReport(
        [FromQuery] int userId,
        [FromQuery] string role,
        [FromQuery] string? periodMode,
        [FromQuery] string? month,
        [FromQuery] string? year,
        [FromQuery(Name = "from")] DateTime? fromDateInput,
        [FromQuery(Name = "to")] DateTime? toDateInput,
        CancellationToken cancellationToken)
    {
        if (userId <= 0)
        {
            return BadRequest("userId is required.");
        }

        if (!string.Equals(role, "accounting", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest("Accounting role is required to generate this report.");
        }

        if (!TryResolveAccountingReportPeriod(
                periodMode,
                month,
                year,
                fromDateInput,
                toDateInput,
                out var fromDate,
                out var toDate,
                out var periodLabel,
                out var errorMessage))
        {
            return BadRequest(errorMessage);
        }

        var rows = await _repository.GetAccountingReportRowsAsync(userId, fromDate, toDate, cancellationToken);
        var workbook = BuildAccountingReportWorkbook(rows);
        var fileName = $"AccountingReport-{SanitizeFileName(periodLabel)}-{GetAuditDate():yyyyMMddHHmmss}.xls";
        return File(workbook, "application/vnd.ms-excel", fileName);
    }

    [HttpGet("business-partners")]
    public async Task<ActionResult<IReadOnlyList<BusinessPartnerDto>>> GetBusinessPartners(
        [FromQuery] int? companyId,
        CancellationToken cancellationToken)
    {
        var businessPartners = await _repository.GetBusinessPartnersAsync(companyId, cancellationToken);
        return Ok(businessPartners);
    }

    [HttpGet("companies")]
    public async Task<ActionResult<IReadOnlyList<CompanyDto>>> GetCompanies(CancellationToken cancellationToken)
    {
        var companies = await _repository.GetCompaniesAsync(cancellationToken);
        return Ok(companies);
    }

    [HttpGet("projects")]
    public async Task<ActionResult<IReadOnlyList<ProjectDto>>> GetProjects(
        [FromQuery] int? companyId,
        CancellationToken cancellationToken)
    {
        var projects = await _repository.GetProjectsAsync(companyId, cancellationToken);
        return Ok(projects);
    }

    [HttpGet("profit-centers")]
    public async Task<ActionResult<IReadOnlyList<ProfitCenterDto>>> GetProfitCenters(
        [FromQuery] int? companyId,
        CancellationToken cancellationToken)
    {
        var profitCenters = await _repository.GetProfitCentersAsync(companyId, cancellationToken);
        return Ok(profitCenters);
    }

    [HttpGet("cost-centers")]
    public async Task<ActionResult<IReadOnlyList<CostCenterDto>>> GetCostCenters(
        [FromQuery] int companyId,
        CancellationToken cancellationToken)
    {
        if (companyId <= 0)
        {
            return BadRequest("companyId is required.");
        }

        var costCenters = await _repository.GetCostCentersAsync(companyId, cancellationToken);
        return Ok(costCenters);
    }

    [HttpGet("expense-types")]
    public async Task<ActionResult<IReadOnlyList<ExpenseTypeDto>>> GetExpenseTypes(CancellationToken cancellationToken)
    {
        var expenseTypes = await _repository.GetExpenseTypesAsync(cancellationToken);
        return Ok(expenseTypes);
    }

    [HttpGet("{printToken}/print")]
    public async Task<IActionResult> PrintDepartmentApprovedRequest(
        string printToken,
        [FromQuery] int userId,
        [FromQuery] string role,
        [FromQuery] string department,
        CancellationToken cancellationToken)
    {
        if (userId <= 0 || string.IsNullOrWhiteSpace(role) || string.IsNullOrWhiteSpace(department))
        {
            return BadRequest("userId, role, and department are required.");
        }

        var cashAdvanceRequestId = TryUnprotectPrintId(printToken);
        if (cashAdvanceRequestId is null)
        {
            return BadRequest("Invalid print token.");
        }

        var requests = await _repository.GetCashAdvanceRequestsAsync(userId, role, department, cancellationToken);
        var request = requests.FirstOrDefault(item => item.CashAdvanceRequestId == cashAdvanceRequestId.Value);
        if (request is null)
        {
            var approvalHistoryRequests = await _repository.GetApprovalHistoryRequestsAsync(userId, role, department, cancellationToken);
            request = approvalHistoryRequests.FirstOrDefault(item => item.CashAdvanceRequestId == cashAdvanceRequestId.Value);
        }

        if (request is null)
        {
            return NotFound();
        }

        var approvalEvent = GetDepartmentApprovalEvent(request);
        if (approvalEvent is null)
        {
            return BadRequest("Request is not available to print until it is approved by the department.");
        }

        var pdfBytes = await _requestPrint.BuildPdfAsync(request, approvalEvent, cancellationToken);
        var fileName = $"ApprovedRequest-{SanitizeFileName(GetReferenceNumber(request))}.pdf";
        Response.Headers[HeaderNames.ContentDisposition] = CreateInlineContentDisposition(fileName);
        return File(pdfBytes, "application/pdf");
    }

    [HttpPost("{cashAdvanceRequestId:int}/liquidation")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> SubmitLiquidation(
        int cashAdvanceRequestId,
        [FromForm] SubmitCashAdvanceLiquidationFormRequest request,
        CancellationToken cancellationToken)
    {
        if (request.AmountSpent <= 0)
        {
            return BadRequest("Amount spent must be greater than zero.");
        }

        var storedAttachments = await SaveAttachmentsAsync(
            cashAdvanceRequestId,
            "liquidation",
            request.Attachments ?? new List<IFormFile>(),
            cancellationToken);

        try
        {
            await _repository.SubmitCashAdvanceLiquidationAsync(
                cashAdvanceRequestId,
                new SubmitCashAdvanceLiquidationRequest(
                    request.UserId,
                    request.AmountSpent,
                    request.Notes,
                    request.ReceiptDetailsJson,
                    request.PettyCashReceiptDetailsJson,
                    request.PettyCashTransportationDetailsJson,
                    request.ReplaceExistingAttachments,
                    storedAttachments),
                cancellationToken);
        }
        catch (SqlException sqlException) when (sqlException.Class <= 16)
        {
            DeleteStoredFiles(storedAttachments);
            return BadRequest(sqlException.Message);
        }
        catch
        {
            DeleteStoredFiles(storedAttachments);
            throw;
        }

        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/rfp-attachment")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> SubmitRfpAttachment(
        int cashAdvanceRequestId,
        [FromForm] SubmitRfpAttachmentFormRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Attachments is null || request.Attachments.All(file => file.Length <= 0))
        {
            return BadRequest("RFP attachment is required.");
        }

        var storedAttachments = await SaveAttachmentsAsync(
            cashAdvanceRequestId,
            "rfp",
            request.Attachments,
            cancellationToken);

        try
        {
            await _repository.SubmitCashAdvanceRfpAttachmentAsync(
                cashAdvanceRequestId,
                new SubmitRfpAttachmentRequest(request.Notes, storedAttachments),
                cancellationToken);
        }
        catch
        {
            DeleteStoredFiles(storedAttachments);
            throw;
        }

        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/transfer")]
    public async Task<IActionResult> TransferRequest(
        int cashAdvanceRequestId,
        TransferCashAdvanceRequest request,
        CancellationToken cancellationToken)
    {
        if (request.ToUserId <= 0)
        {
            return BadRequest("Transfer target user is required.");
        }

        if (!request.TransferWholeRequest && request.Amount <= 0)
        {
            return BadRequest("Partial transfer amount must be greater than zero.");
        }

        await _repository.TransferCashAdvanceAsync(cashAdvanceRequestId, request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/transfer-response")]
    public async Task<IActionResult> RespondToTransfer(
        int cashAdvanceRequestId,
        TransferAcknowledgementRequest request,
        CancellationToken cancellationToken)
    {
        if (request.ReceiverUserId <= 0)
        {
            return BadRequest("Receiver user is required.");
        }

        await _repository.RespondToCashAdvanceTransferAsync(cashAdvanceRequestId, request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/department-decision")]
    public async Task<IActionResult> DepartmentDecision(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Approved &&
            string.Equals(request.RfpDecision, "waive", StringComparison.OrdinalIgnoreCase) &&
            string.IsNullOrWhiteSpace(request.Notes))
        {
            return BadRequest("Waive RFP reason is required.");
        }

        try
        {
            await _repository.DecideCashAdvanceDepartmentAsync(cashAdvanceRequestId, request, cancellationToken);
        }
        catch (InvalidOperationException error)
        {
            return BadRequest(error.Message);
        }
        return NoContent();
    }

    [HttpPost("petty-cash")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> CreatePettyCashRequest(
        [FromForm] CreatePettyCashFormRequest request,
        CancellationToken cancellationToken)
    {
        var requestType = request.RequestType?.Trim() ?? string.Empty;

        if (string.Equals(requestType, "petty_cash", StringComparison.OrdinalIgnoreCase) && request.CompanyId is not > 0)
        {
            return BadRequest("Company is required for petty cash reimbursement.");
        }

        if (!string.Equals(requestType, "petty_cash", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(requestType, "petty_cash_advance", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest("Request type must be petty_cash or petty_cash_advance.");
        }

        if (request.RequestorUserId <= 0)
        {
            return BadRequest("Requestor user is required.");
        }

        if (request.CustodianUserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        if (request.Amount <= 0 || request.Amount > PettyCashRequestLimit)
        {
            return BadRequest("Petty cash amount must be greater than zero and must not exceed PHP 5,000.");
        }

        if (string.Equals(requestType, "petty_cash", StringComparison.OrdinalIgnoreCase) &&
            (request.Attachments is null || request.Attachments.All(file => file.Length <= 0)))
        {
            return BadRequest("Attachment is required.");
        }

        if (!TryDeserializeFormList<PettyCashReceiptDetailInputDto>(
                request.PettyCashReceiptDetailsJson,
                "receipt details",
                out var receiptDetails,
                out var receiptDetailsError))
        {
            return BadRequest(receiptDetailsError);
        }

        if (!TryDeserializeFormList<PettyCashTransportationDetailInputDto>(
                request.PettyCashTransportationDetailsJson,
                "transportation details",
                out var transportationDetails,
                out var transportationDetailsError))
        {
            return BadRequest(transportationDetailsError);
        }

        if (string.Equals(requestType, "petty_cash", StringComparison.OrdinalIgnoreCase))
        {
            if (receiptDetails.Count + transportationDetails.Count == 0)
            {
                return BadRequest("At least one receipt or transportation row is required for petty cash reimbursement.");
            }

            if (receiptDetails.Any(detail =>
                    string.IsNullOrWhiteSpace(detail.OrNumber) ||
                    string.IsNullOrWhiteSpace(detail.Company) ||
                    string.IsNullOrWhiteSpace(detail.Tin) ||
                    string.IsNullOrWhiteSpace(detail.Address) ||
                    (string.IsNullOrWhiteSpace(detail.NatureOfExpenseCode) &&
                     string.IsNullOrWhiteSpace(detail.NatureOfExpense)) ||
                    (string.IsNullOrWhiteSpace(detail.CostCenterCode) &&
                     string.IsNullOrWhiteSpace(detail.CostCenter)) ||
                    detail.Amount <= 0 ||
                    detail.OrDate == default))
            {
                return BadRequest("Complete every receipt row before submitting petty cash reimbursement.");
            }

            if (transportationDetails.Any(detail =>
                    string.IsNullOrWhiteSpace(detail.Description) ||
                    string.IsNullOrWhiteSpace(detail.From) ||
                    string.IsNullOrWhiteSpace(detail.To) ||
                    detail.TransactionDate == default ||
                    detail.Amount <= 0))
            {
                return BadRequest("Complete every transportation row before submitting petty cash reimbursement.");
            }

            var requestTotal = receiptDetails.Sum(detail => detail.Amount) +
                transportationDetails.Sum(detail => detail.Amount);
            if (requestTotal + 0.01m < request.Amount)
            {
                return BadRequest("Petty cash actual spent must be equal to or greater than the reimbursement amount.");
            }

            var excessAmount = requestTotal - request.Amount;
            if (excessAmount > PettyCashRequestLimit)
            {
                return BadRequest("The reimbursement excess must not exceed the petty cash request cap.");
            }
        }

        if (string.IsNullOrWhiteSpace(request.Purpose))
        {
            return BadRequest("Purpose is required.");
        }

        var cashAdvanceRequestId = await _repository.CreatePettyCashRequestAsync(
            new CreatePettyCashRequest(
                requestType,
                request.RequestorUserId,
                request.CustodianUserId,
                request.Amount,
                request.Purpose,
                JsonSerializer.Serialize(receiptDetails, FormJsonOptions),
                JsonSerializer.Serialize(transportationDetails, FormJsonOptions),
                request.CompanyId),
            cancellationToken);

        var storedAttachments = await SaveAttachmentsAsync(
            cashAdvanceRequestId,
            "petty-cash",
            request.Attachments ?? new List<IFormFile>(),
            cancellationToken);

        try
        {
            if (storedAttachments.Count > 0)
            {
                await _repository.AddCashAdvanceAttachmentsAsync(cashAdvanceRequestId, storedAttachments, cancellationToken);
            }
        }
        catch
        {
            DeleteStoredFiles(storedAttachments);
            throw;
        }

        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/custodian-decision")]
    public async Task<IActionResult> CustodianDecision(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken)
    {
        if (request.UserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        try
        {
            await _repository.DecidePettyCashCustodianAsync(cashAdvanceRequestId, request, cancellationToken);
        }
        catch (Microsoft.Data.SqlClient.SqlException error) when (error.Number is 51225 or 51226)
        {
            return BadRequest(error.Message);
        }
        return NoContent();
    }

    [HttpPost("petty-cash/replenishment")]
    public async Task<IActionResult> CreatePettyCashReplenishment(
        CreatePettyCashReplenishmentRequest request,
        CancellationToken cancellationToken)
    {
        if (request.CustodianUserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        if (request.Amount <= 0)
        {
            return BadRequest("Replenishment amount must be greater than zero.");
        }

        await _repository.CreatePettyCashReplenishmentAsync(request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/petty-cash/replenishment-cv")]
    public async Task<IActionResult> SubmitPettyCashReplenishmentCv(
        int cashAdvanceRequestId,
        SubmitPettyCashReplenishmentCvRequest request,
        CancellationToken cancellationToken)
    {
        if (request.CustodianUserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        if (string.IsNullOrWhiteSpace(request.CvNumber))
        {
            return BadRequest("CV Number is required.");
        }

        await _repository.SubmitPettyCashReplenishmentCvAsync(cashAdvanceRequestId, request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/cashier-receipt")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> CreateCashierReceipt(
        int cashAdvanceRequestId,
        [FromForm] CashierReceiptFormRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ReceiptNumber))
        {
            return BadRequest("Receipt number is required.");
        }
        if (request.DepositAmount is < 0)
        {
            return BadRequest("Deposit amount must be zero or greater.");
        }

        var depositSlip = request.DepositSlip ?? request.Attachment;

        if (depositSlip is not null &&
            (request.DepositDate is null ||
             request.DepositAmount is not > 0 ||
             string.IsNullOrWhiteSpace(request.DepositoryBank)))
        {
            return BadRequest("Deposit date, deposit amount, and depository bank are required when uploading the Deposit Slip/AR attachment.");
        }

        var storedDepositSlips = depositSlip is null
            ? Array.Empty<StoredAttachmentInput>()
            : await SaveAttachmentsAsync(
                cashAdvanceRequestId,
                "deposit-slips",
                new[] { depositSlip },
                cancellationToken);

        var storedDepositSlip = storedDepositSlips.SingleOrDefault();

        try
        {
            await _repository.CreateCashierReceiptAsync(
                cashAdvanceRequestId,
                new CashierReceiptRequest(
                    request.CashierUserId,
                    request.ReceiptNumber,
                    null,
                    storedDepositSlip,
                    request.DepositDate,
                    request.DepositAmount,
                    request.DepositoryBank,
                    request.Notes),
                cancellationToken);
        }
        catch
        {
            DeleteStoredFiles(storedDepositSlips);
            throw;
        }

        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/custodian-receipt")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> CreateCustodianReceipt(
        int cashAdvanceRequestId,
        [FromForm] CustodianReceiptFormRequest request,
        CancellationToken cancellationToken)
    {
        if (request.CustodianUserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        if (string.IsNullOrWhiteSpace(request.ReceiptNumber))
        {
            return BadRequest("Receipt number is required.");
        }

        await _repository.CreateCustodianReceiptAsync(
            cashAdvanceRequestId,
            new CustodianReceiptRequest(
                request.CustodianUserId,
                request.ReceiptNumber,
                request.Notes),
            cancellationToken);

        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/accounting-decision")]
    public async Task<IActionResult> AccountingDecision(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken)
    {
        await _repository.DecideCashAdvanceAccountingAsync(cashAdvanceRequestId, request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{cashAdvanceRequestId:int}/cashier-closure")]
    public async Task<IActionResult> CashierClosure(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken)
    {
        if (request.UserId <= 0)
        {
            return BadRequest("Cashier user is required.");
        }

        await _repository.CloseCashierLiquidationAsync(cashAdvanceRequestId, request, cancellationToken);
        return NoContent();
    }

    [HttpGet("attachments/{attachmentId:int}")]
    public async Task<IActionResult> DownloadAttachment(
        int attachmentId,
        [FromQuery] bool preview,
        CancellationToken cancellationToken)
    {
        var attachment = await _repository.GetCashAdvanceAttachmentAsync(attachmentId, cancellationToken);
        return attachment is null ? NotFound() : CreateDownloadResult(attachment, preview);
    }

    [HttpGet("cashier-receipts/{receiptId:int}/attachment")]
    public async Task<IActionResult> DownloadCashierReceiptAttachment(
        int receiptId,
        [FromQuery] bool preview,
        CancellationToken cancellationToken)
    {
        var attachment = await _repository.GetCashierReceiptAttachmentAsync(receiptId, cancellationToken);
        return attachment is null ? NotFound() : CreateDownloadResult(attachment, preview);
    }

    [HttpGet("cashier-receipts/{receiptId:int}/deposit-slip")]
    public async Task<IActionResult> DownloadCashierDepositSlipAttachment(
        int receiptId,
        [FromQuery] bool preview,
        CancellationToken cancellationToken)
    {
        var attachment = await _repository.GetCashierDepositSlipAttachmentAsync(receiptId, cancellationToken);
        return attachment is null ? NotFound() : CreateDownloadResult(attachment, preview);
    }

    private async Task<IReadOnlyList<StoredAttachmentInput>> SaveAttachmentsAsync(
        int cashAdvanceRequestId,
        string category,
        IEnumerable<IFormFile> files,
        CancellationToken cancellationToken)
    {
        var storedAttachments = new List<StoredAttachmentInput>();

        foreach (var file in files.Where(file => file.Length > 0))
        {
            var originalFileName = SanitizeFileName(Path.GetFileName(file.FileName));
            var extension = Path.GetExtension(originalFileName);
            var storedFileName = $"{Guid.NewGuid():N}{extension}";
            var relativePath = Path.Combine(category, cashAdvanceRequestId.ToString(), storedFileName).Replace('\\', '/');
            var folder = Path.Combine(GetUploadsRoot(), category, cashAdvanceRequestId.ToString());
            Directory.CreateDirectory(folder);

            var fullPath = Path.Combine(folder, storedFileName);
            await using var stream = System.IO.File.Create(fullPath);
            await file.CopyToAsync(stream, cancellationToken);

            storedAttachments.Add(new StoredAttachmentInput(
                originalFileName,
                storedFileName,
                relativePath,
                string.IsNullOrWhiteSpace(file.ContentType) ? "application/octet-stream" : file.ContentType,
                file.Length));
        }

        return storedAttachments;
    }

    private static bool TryDeserializeFormList<T>(
        string? json,
        string label,
        out IReadOnlyList<T> rows,
        out string errorMessage)
    {
        rows = Array.Empty<T>();
        errorMessage = string.Empty;

        if (string.IsNullOrWhiteSpace(json))
        {
            return true;
        }

        try
        {
            rows = JsonSerializer.Deserialize<IReadOnlyList<T>>(json, FormJsonOptions) ?? Array.Empty<T>();
            return true;
        }
        catch (JsonException)
        {
            errorMessage = $"Invalid petty cash {label}.";
            return false;
        }
    }

    private async Task<StoredAttachmentInput> SaveGeneratedPdfAsync(
        int cashAdvanceRequestId,
        string receiptNumber,
        int cashierUserId,
        string? notes,
        CancellationToken cancellationToken)
    {
        var safeReceiptNumber = SanitizeFileName(receiptNumber);
        var originalFileName = $"AcknowledgementReceipt-{safeReceiptNumber}.pdf";
        var storedFileName = $"{Guid.NewGuid():N}.pdf";
        var relativePath = Path.Combine("acknowledgement-receipts", cashAdvanceRequestId.ToString(), storedFileName).Replace('\\', '/');
        var folder = Path.Combine(GetUploadsRoot(), "acknowledgement-receipts", cashAdvanceRequestId.ToString());
        Directory.CreateDirectory(folder);

        var fullPath = Path.Combine(folder, storedFileName);
        var html = await BuildAcknowledgementReceiptHtmlAsync(
            receiptNumber,
            cashAdvanceRequestId,
            cashierUserId,
            notes,
            cancellationToken);

        var renderedFromHtml = await TryRenderHtmlToPdfAsync(html, fullPath, cancellationToken);
        if (!renderedFromHtml)
        {
            var fallbackPdfBytes = BuildFallbackAcknowledgementReceiptPdf(
                receiptNumber,
                cashAdvanceRequestId,
                cashierUserId,
                notes);
            await System.IO.File.WriteAllBytesAsync(fullPath, fallbackPdfBytes, cancellationToken);
        }

        var fileSizeBytes = new FileInfo(fullPath).Length;

        return new StoredAttachmentInput(
            originalFileName,
            storedFileName,
            relativePath,
            "application/pdf",
            fileSizeBytes);
    }

    private CashAdvanceWorkflowRequestDto AddPrintToken(CashAdvanceWorkflowRequestDto request) =>
        request with
        {
            PrintToken = GetDepartmentApprovalEvent(request) is null
                ? string.Empty
                : _printIdProtector.Protect(request.CashAdvanceRequestId.ToString(CultureInfo.InvariantCulture))
        };

    private int? TryUnprotectPrintId(string printToken)
    {
        try
        {
            var unprotectedValue = _printIdProtector.Unprotect(printToken);
            return int.TryParse(unprotectedValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var requestId)
                ? requestId
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static byte[] BuildAccountingReportWorkbook(IReadOnlyList<AccountingReportRowDto> rows)
    {
        var workbook = new StringBuilder();
        workbook.AppendLine("""
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    table { border-collapse: collapse; font-family: Arial, Helvetica, sans-serif; font-size: 12px; }
    th { background: #17243f; color: #ffffff; font-weight: 700; }
    th, td { border: 1px solid #9ca8b3; padding: 6px 8px; }
    .number { mso-number-format: "0.00"; text-align: right; }
    .text { mso-number-format: "\@"; }
  </style>
</head>
<body>
  <table>
    <thead>
      <tr>
        <th>RequestNumber</th>
        <th>VendorCode</th>
        <th>Description</th>
        <th>ProjectCode</th>
        <th>ProfitCenterCode</th>
        <th>Amount</th>
        <th>InvoiceRef</th>
        <th>ExpenseTypeCode</th>
      </tr>
    </thead>
    <tbody>
""");

        foreach (var row in rows)
        {
            workbook.AppendLine(CultureInfo.InvariantCulture, $"""
      <tr>
        <td class="text">{HtmlEncode(row.RequestNumber)}</td>
        <td class="text">{HtmlEncode(row.VendorCode)}</td>
        <td>{HtmlEncode(row.Description)}</td>
        <td class="text">{HtmlEncode(row.ProjectCode)}</td>
        <td class="text">{HtmlEncode(row.ProfitCenterCode)}</td>
        <td class="number">{row.Amount.ToString("0.00", CultureInfo.InvariantCulture)}</td>
        <td class="text">{HtmlEncode(row.InvoiceRef)}</td>
        <td class="text">{HtmlEncode(row.ExpenseTypeCode)}</td>
      </tr>
""");
        }

        workbook.AppendLine("""
    </tbody>
  </table>
</body>
</html>
""");

        return Encoding.UTF8.GetBytes(workbook.ToString());
    }

    private static bool TryResolveAccountingReportPeriod(
        string? periodMode,
        string? month,
        string? year,
        DateTime? fromDateInput,
        DateTime? toDateInput,
        out DateTime? fromDate,
        out DateTime? toDate,
        out string periodLabel,
        out string errorMessage)
    {
        fromDate = null;
        toDate = null;
        periodLabel = "All";
        errorMessage = string.Empty;

        switch ((periodMode ?? "all").Trim().ToLowerInvariant())
        {
            case "all":
                return true;

            case "month":
                if (!DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var monthDate))
                {
                    errorMessage = "A report month in yyyy-MM format is required.";
                    return false;
                }

                fromDate = new DateTime(monthDate.Year, monthDate.Month, 1);
                toDate = fromDate.Value.AddMonths(1).AddDays(-1);
                periodLabel = fromDate.Value.ToString("yyyy-MM", CultureInfo.InvariantCulture);
                return true;

            case "year":
                if (!int.TryParse(year, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedYear) ||
                    parsedYear < 1900 ||
                    parsedYear > 9999)
                {
                    errorMessage = "A valid report year is required.";
                    return false;
                }

                fromDate = new DateTime(parsedYear, 1, 1);
                toDate = new DateTime(parsedYear, 12, 31);
                periodLabel = parsedYear.ToString(CultureInfo.InvariantCulture);
                return true;

            case "range":
                if (fromDateInput is null || toDateInput is null)
                {
                    errorMessage = "From and To dates are required.";
                    return false;
                }

                fromDate = fromDateInput.Value.Date;
                toDate = toDateInput.Value.Date;
                if (fromDate > toDate)
                {
                    errorMessage = "From date cannot be later than To date.";
                    return false;
                }

                periodLabel = $"{fromDate.Value:yyyy-MM-dd}-to-{toDate.Value:yyyy-MM-dd}";
                return true;

            default:
                errorMessage = "Invalid report period mode.";
                return false;
        }
    }

    private async Task<string> BuildAcknowledgementReceiptHtmlAsync(
        string receiptNumber,
        int cashAdvanceRequestId,
        int cashierUserId,
        string? notes,
        CancellationToken cancellationToken)
    {
        var templatePath = Path.Combine(_environment.ContentRootPath, "Templates", "AcknowledgementReceipt.html");
        var template = System.IO.File.Exists(templatePath)
            ? await System.IO.File.ReadAllTextAsync(templatePath, cancellationToken)
            : DefaultAcknowledgementReceiptTemplate;

        var issuedAt = GetAuditDate();
        var tokens = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["ReceiptNumber"] = HtmlEncode(receiptNumber),
            ["CashAdvanceRequestId"] = HtmlEncode(cashAdvanceRequestId.ToString(CultureInfo.InvariantCulture)),
            ["CashierUserId"] = HtmlEncode(cashierUserId.ToString(CultureInfo.InvariantCulture)),
            ["IssuedAt"] = HtmlEncode(issuedAt.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)),
            ["IssuedDate"] = HtmlEncode(issuedAt.ToString("MMMM dd, yyyy", CultureInfo.InvariantCulture)),
            ["Notes"] = HtmlEncodeMultiline(string.IsNullOrWhiteSpace(notes) ? "No notes provided." : notes)
        };

        foreach (var token in tokens)
        {
            template = template.Replace("{{" + token.Key + "}}", token.Value, StringComparison.OrdinalIgnoreCase);
        }

        return template;
    }

    private static async Task<bool> TryRenderHtmlToPdfAsync(
        string html,
        string pdfPath,
        CancellationToken cancellationToken)
    {
        var browserPath = FindHtmlToPdfBrowserPath();
        if (browserPath is null)
        {
            return false;
        }

        var renderRoot = Path.Combine(Path.GetTempPath(), "FundManagementAPI", "pdf-render");
        Directory.CreateDirectory(renderRoot);
        var renderId = Guid.NewGuid().ToString("N");
        var htmlPath = Path.Combine(renderRoot, renderId + ".html");
        var userDataDirectory = Path.Combine(renderRoot, renderId + "-profile");

        try
        {
            await System.IO.File.WriteAllTextAsync(htmlPath, html, new UTF8Encoding(false), cancellationToken);
            Directory.CreateDirectory(userDataDirectory);

            var startInfo = new ProcessStartInfo(browserPath)
            {
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false
            };

            startInfo.ArgumentList.Add("--headless=new");
            startInfo.ArgumentList.Add("--disable-gpu");
            startInfo.ArgumentList.Add("--no-first-run");
            startInfo.ArgumentList.Add("--disable-background-networking");
            startInfo.ArgumentList.Add("--disable-extensions");
            startInfo.ArgumentList.Add("--no-pdf-header-footer");
            startInfo.ArgumentList.Add("--print-to-pdf-no-header");
            startInfo.ArgumentList.Add("--user-data-dir=" + userDataDirectory);
            startInfo.ArgumentList.Add("--print-to-pdf=" + pdfPath);
            startInfo.ArgumentList.Add(new Uri(htmlPath).AbsoluteUri);

            if (System.IO.File.Exists(pdfPath))
            {
                System.IO.File.Delete(pdfPath);
            }

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

            try
            {
                await process.WaitForExitAsync(cancellationToken);
            }
            catch
            {
                TryKillProcess(process);
                throw;
            }

            await Task.WhenAll(outputTask, errorTask);

            return process.ExitCode == 0 &&
                System.IO.File.Exists(pdfPath) &&
                new FileInfo(pdfPath).Length > 0;
        }
        catch when (!cancellationToken.IsCancellationRequested)
        {
            return false;
        }
        finally
        {
            TryDeleteFile(htmlPath);
            TryDeleteDirectory(userDataDirectory);
        }
    }

    private static string? FindHtmlToPdfBrowserPath()
    {
        var candidates = new[]
        {
            Environment.GetEnvironmentVariable("FMS_HTML_TO_PDF_BROWSER"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Google", "Chrome", "Application", "chrome.exe")
        };

        return candidates.FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && System.IO.File.Exists(path));
    }

    private static void TryKillProcess(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Ignore cleanup failures; the request cancellation or render failure is already being handled.
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (System.IO.File.Exists(path))
            {
                System.IO.File.Delete(path);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private static byte[] BuildSimplePdf(IEnumerable<string> lines)
    {
        var contentBuilder = new StringBuilder();
        var y = 760;
        foreach (var line in lines.Where(line => line.Length > 0).Take(28))
        {
            var fontSize = line == "DEPARTMENT APPROVED REQUEST" || line == "ACKNOWLEDGEMENT RECEIPT" ? 16 : 11;
            contentBuilder.Append(CultureInfo.InvariantCulture, $"BT /F1 {fontSize} Tf 72 {y} Td ({EscapePdfText(line)}) Tj ET\n");
            y -= 24;
        }

        var content = contentBuilder.ToString();
        var objects = new[]
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            $"<< /Length {Encoding.ASCII.GetByteCount(content)} >>\nstream\n{content}endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        };

        var pdf = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int> { 0 };
        foreach (var item in objects.Select((value, index) => new { value, index }))
        {
            offsets.Add(Encoding.ASCII.GetByteCount(pdf.ToString()));
            pdf.Append(CultureInfo.InvariantCulture, $"{item.index + 1} 0 obj\n{item.value}\nendobj\n");
        }

        var xrefOffset = Encoding.ASCII.GetByteCount(pdf.ToString());
        pdf.Append(CultureInfo.InvariantCulture, $"xref\n0 {objects.Length + 1}\n");
        pdf.Append("0000000000 65535 f \n");
        foreach (var offset in offsets.Skip(1))
        {
            pdf.Append(CultureInfo.InvariantCulture, $"{offset:0000000000} 00000 n \n");
        }

        pdf.Append(CultureInfo.InvariantCulture, $"trailer\n<< /Size {objects.Length + 1} /Root 1 0 R >>\nstartxref\n{xrefOffset}\n%%EOF");
        return Encoding.ASCII.GetBytes(pdf.ToString());
    }

    private static CashAdvanceHistoryDto? GetDepartmentApprovalEvent(CashAdvanceWorkflowRequestDto request) =>
        request.History.Reverse().FirstOrDefault(history => IsDepartmentApprovalAction(history.Action));

    private static bool IsDepartmentApprovalAction(string action) =>
        action.Equals("approved_by_department_head", StringComparison.OrdinalIgnoreCase) ||
        action.Equals("rfp_created", StringComparison.OrdinalIgnoreCase) ||
        action.Equals("rfp_waived", StringComparison.OrdinalIgnoreCase);

    private static string GetReferenceNumber(CashAdvanceWorkflowRequestDto request) =>
        string.IsNullOrWhiteSpace(request.RfpRequestNumber) ? request.RequestNumber : request.RfpRequestNumber;

    private static string FormatDepartmentApprover(CashAdvanceWorkflowRequestDto request, CashAdvanceHistoryDto approvalEvent)
    {
        var approverName = string.IsNullOrWhiteSpace(request.RequestorDepartmentApproverName)
            ? approvalEvent.ActorName
            : request.RequestorDepartmentApproverName;

        approverName = string.IsNullOrWhiteSpace(approverName)
            ? "Department approver"
            : approverName;

        return $"{approverName} on {FormatDateTime(approvalEvent.AuditDate)}";
    }

    private static string FormatCurrency(decimal amount) =>
        "PHP " + amount.ToString("N2", CultureInfo.InvariantCulture);

    private static string FormatDate(DateTime date) =>
        date.ToString("MMM dd, yyyy", CultureInfo.InvariantCulture);

    private static string FormatDateTime(DateTime date) =>
        date.ToString("MMM dd, yyyy hh:mm tt", CultureInfo.InvariantCulture);

    private static DateTime GetAuditDate() => DateTime.Now;

    private static byte[] BuildFallbackAcknowledgementReceiptPdf(
        string receiptNumber,
        int cashAdvanceRequestId,
        int cashierUserId,
        string? notes)
    {
        var lines = new[]
        {
            "ACKNOWLEDGEMENT RECEIPT",
            $"Receipt Number: {receiptNumber}",
            $"Cash Advance Request ID: {cashAdvanceRequestId}",
            $"Cashier User ID: {cashierUserId}",
            $"Issued: {GetAuditDate().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)}",
            "This acknowledges receipt of the cash return for the referenced cash advance request.",
            string.IsNullOrWhiteSpace(notes) ? "" : $"Notes: {notes}"
        }.Where(line => line.Length > 0).ToArray();

        return BuildSimplePdf(lines);
    }

    private static string EscapePdfText(string value) =>
        value.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");

    private static string HtmlEncode(string value) => WebUtility.HtmlEncode(value);

    private static string HtmlEncodeMultiline(string value) =>
        HtmlEncode(value)
            .Replace("\r\n", "<br>", StringComparison.Ordinal)
            .Replace("\n", "<br>", StringComparison.Ordinal)
            .Replace("\r", "<br>", StringComparison.Ordinal);

    private const string DefaultAcknowledgementReceiptTemplate = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Acknowledgement Receipt {{ReceiptNumber}}</title>
  <style>
    @page { size: A4; margin: 18mm; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: #17243f;
      font-family: Arial, Helvetica, sans-serif;
      font-size: 13px;
      line-height: 1.45;
    }
  </style>
</head>
<body>
  <h1>Acknowledgement Receipt</h1>
  <p>Receipt Number: <strong>{{ReceiptNumber}}</strong></p>
  <p>Cash Advance Request ID: {{CashAdvanceRequestId}}</p>
  <p>Cashier User ID: {{CashierUserId}}</p>
  <p>Issued: {{IssuedAt}}</p>
  <p>This acknowledges receipt of the cash return for the referenced cash advance request.</p>
  <p>Notes: {{Notes}}</p>
</body>
</html>
""";

    private IActionResult CreateDownloadResult(StoredFileDownload attachment, bool preview)
    {
        var fullPath = GetStoredFilePath(attachment.RelativePath);

        if (fullPath is null || !System.IO.File.Exists(fullPath))
        {
            return NotFound();
        }

        if (preview)
        {
            Response.Headers[HeaderNames.ContentDisposition] = CreateInlineContentDisposition(attachment.OriginalFileName);
            return PhysicalFile(fullPath, GetBrowserContentType(attachment, fullPath), enableRangeProcessing: true);
        }

        return PhysicalFile(fullPath, GetBrowserContentType(attachment, fullPath), attachment.OriginalFileName);
    }

    private void DeleteStoredFiles(IEnumerable<StoredAttachmentInput> attachments)
    {
        foreach (var attachment in attachments)
        {
            var fullPath = GetStoredFilePath(attachment.RelativePath);

            if (fullPath is not null && System.IO.File.Exists(fullPath))
            {
                System.IO.File.Delete(fullPath);
            }
        }
    }

    private string? GetStoredFilePath(string relativePath)
    {
        var uploadsRoot = Path.GetFullPath(GetUploadsRoot());
        var uploadsRootWithSeparator = uploadsRoot.EndsWith(Path.DirectorySeparatorChar)
            ? uploadsRoot
            : uploadsRoot + Path.DirectorySeparatorChar;
        var normalizedRelativePath = relativePath.Replace('/', Path.DirectorySeparatorChar);
        var fullPath = Path.GetFullPath(Path.Combine(uploadsRoot, normalizedRelativePath));

        return fullPath.StartsWith(uploadsRootWithSeparator, StringComparison.OrdinalIgnoreCase) ? fullPath : null;
    }

    private string GetUploadsRoot() => Path.Combine(_environment.ContentRootPath, "Uploads");

    private static string GetBrowserContentType(StoredFileDownload attachment, string fullPath)
    {
        if (!string.IsNullOrWhiteSpace(attachment.ContentType) &&
            !attachment.ContentType.Equals("application/octet-stream", StringComparison.OrdinalIgnoreCase))
        {
            return attachment.ContentType;
        }

        if (ContentTypeProvider.TryGetContentType(attachment.OriginalFileName, out var originalFileContentType))
        {
            return originalFileContentType;
        }

        return ContentTypeProvider.TryGetContentType(fullPath, out var storedFileContentType)
            ? storedFileContentType
            : "application/octet-stream";
    }

    private static string CreateInlineContentDisposition(string fileName)
    {
        var safeFileName = SanitizeFileName(fileName);
        var escapedFileName = safeFileName.Replace("\\", "\\\\").Replace("\"", "\\\"");
        return $"inline; filename=\"{escapedFileName}\"; filename*=UTF-8''{Uri.EscapeDataString(safeFileName)}";
    }

    private static string SanitizeFileName(string fileName)
    {
        var invalidCharacters = Path.GetInvalidFileNameChars();
        var sanitized = new string(fileName.Select(character => invalidCharacters.Contains(character) ? '_' : character).ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "attachment" : sanitized;
    }
}
