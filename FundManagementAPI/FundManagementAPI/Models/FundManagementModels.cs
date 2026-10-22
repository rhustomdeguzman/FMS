using Microsoft.AspNetCore.Http;

namespace FundManagementAPI.Models;

public sealed record AppUserDto(
    int UserId,
    string Username,
    string DisplayName,
    string Department,
    string Role,
    string Title,
    bool IsActive,
    decimal? PettyCashFundAmount,
    int? RoleCode,
    int? DepartmentCode,
    IReadOnlyList<int> DepartmentGroups);

public sealed record LoginRequest(
    string Username,
    string Password);

public sealed record LoginResponseDto(
    AppUserDto User,
    string Message);

public sealed record CreateAppUserRequest(
    int AdminUserId,
    string Username,
    string Password,
    string DisplayName,
    string Department,
    string Role,
    string Title,
    decimal? PettyCashFundAmount);

public sealed record UpdateAppUserRequest(
    int AdminUserId,
    string Username,
    string DisplayName,
    string Department,
    string Role,
    string Title,
    string? Password,
    decimal? PettyCashFundAmount);

public sealed record UpdateCustodianFundRequest(
    int AdminUserId,
    decimal PettyCashFundAmount);

public sealed record DepartmentCustodianAssignmentDto(
    int DepartmentCode,
    string DepartmentName,
    int? CustodianUserId,
    string? CustodianName,
    string? CustodianDepartment,
    decimal? CustodianFundAmount);

public sealed record UpdateDepartmentCustodianRequest(
    int AdminUserId,
    int CustodianUserId);

public sealed record CashAdvanceAttachmentDto(
    int AttachmentId,
    string FileName,
    string ContentType,
    long FileSizeBytes);

public sealed record CashAdvanceReceiptDetailDto(
    int ReceiptDetailId,
    string? VendorCode,
    string Vendor,
    string Description,
    string? ProjectCode,
    string Project,
    string? ProfitCenterCode,
    string ProfitCenter,
    decimal Amount,
    string InvoiceRef,
    string? ExpenseTypeCode,
    string ExpenseType,
    DateTime AuditDate);

public sealed record PettyCashReceiptDetailDto(
    int PettyCashReceiptDetailId,
    string OrNumber,
    string Company,
    string Tin,
    string Address,
    string? NatureOfExpenseCode,
    string NatureOfExpense,
    string? CostCenterCode,
    string CostCenter,
    string? TaxType,
    decimal Amount,
    DateTime OrDate,
    DateTime AuditDate);

public sealed record PettyCashReceiptDetailInputDto(
    string OrNumber,
    string Company,
    string Tin,
    string Address,
    string? NatureOfExpenseCode,
    string NatureOfExpense,
    string? CostCenterCode,
    string CostCenter,
    string? TaxType,
    decimal Amount,
    DateTime OrDate);

public sealed record PettyCashTransportationDetailDto(
    int PettyCashTransportationDetailId,
    string Description,
    string From,
    string To,
    DateTime TransactionDate,
    decimal Amount,
    DateTime AuditDate);

public sealed record PettyCashTransportationDetailInputDto(
    string Description,
    string From,
    string To,
    DateTime TransactionDate,
    decimal Amount);

public sealed record BusinessPartnerDto(
    string BpCode,
    string BpName);

public sealed record CompanyDto(
    int? CompanyId,
    string Name);

public sealed record ProjectDto(
    string ProjCode,
    string ProjName);

public sealed record ProfitCenterDto(
    string OcrCode,
    string OcrName);

public sealed record CostCenterDto(
    string CostCenterCode,
    string CostCenterName);

public sealed record ExpenseTypeDto(
    string ExpenseCode,
    string ExpenseName);

public sealed record AccountingReportRowDto(
    string RequestNumber,
    string VendorCode,
    string Description,
    string ProjectCode,
    string ProfitCenterCode,
    decimal Amount,
    string InvoiceRef,
    string ExpenseTypeCode);

public sealed record CashierReceiptDto(
    int ReceiptId,
    string ReceiptNumber,
    decimal ReturnAmount,
    string? AttachmentFileName,
    string? AttachmentContentType,
    long? AttachmentFileSizeBytes,
    string? DepositSlipFileName,
    string? DepositSlipContentType,
    long? DepositSlipFileSizeBytes,
    DateTime? DepositDate,
    decimal? DepositAmount,
    string? DepositoryBank,
    DateTime AuditDate);

public sealed record CashAdvanceHistoryDto(
    int HistoryId,
    string Action,
    int? ActorUserId,
    string? ActorName,
    string? ActorDepartment,
    decimal? Amount,
    string? Notes,
    DateTime AuditDate);

public sealed record CashAdvancePendingTransferDto(
    int PendingTransferId,
    int PendingTransferFromUserId,
    string PendingTransferFromName,
    string PendingTransferFromDepartment,
    int PendingTransferToUserId,
    string PendingTransferToName,
    string PendingTransferToDepartment,
    decimal PendingTransferAmount,
    bool PendingTransferIsWholeRequest,
    string? PendingTransferNotes,
    DateTime PendingTransferRequestedAt);

public sealed record CashAdvanceTransferAllocationDto(
    int TransferId,
    int TransferFromUserId,
    string TransferFromName,
    string TransferFromDepartment,
    int TransferToUserId,
    string TransferToName,
    string TransferToDepartment,
    decimal TransferAmount,
    bool TransferIsWholeRequest,
    string TransferStatus,
    string? TransferNotes,
    string? TransferResponseNotes,
    DateTime TransferRequestedAt,
    DateTime? TransferRespondedAt);

public sealed record CashAdvanceWorkflowRequestDto(
    int CashAdvanceRequestId,
    int? OriginalCashAdvanceRequestId,
    string RequestNumber,
    string? RfpRequestNumber,
    string? CvNumber,
    int? CompanyId,
    string? CompanyCode,
    string RequestType,
    string SourceSystem,
    decimal Amount,
    decimal RemainingAmount,
    decimal? AmountSpent,
    decimal? ReturnAmount,
    decimal? ExcessAmount,
    string Purpose,
    string Department,
    string Status,
    int RequestorUserId,
    string RequestorName,
    string? RequestorDepartmentApproverName,
    int? CustodianUserId,
    string? CustodianName,
    string? CustodianDepartment,
    int CurrentOwnerUserId,
    string CurrentOwnerName,
    string CurrentOwnerDepartment,
    int? PendingTransferId,
    int? PendingTransferFromUserId,
    string? PendingTransferFromName,
    string? PendingTransferFromDepartment,
    int? PendingTransferToUserId,
    string? PendingTransferToName,
    string? PendingTransferToDepartment,
    decimal? PendingTransferAmount,
    bool? PendingTransferIsWholeRequest,
    string? PendingTransferNotes,
    DateTime? PendingTransferRequestedAt,
    DateTime AuditDate,
    DateTime? DueDate,
    DateTime? LiquidatedAt,
    DateTime? UpdatedAt,
    IReadOnlyList<CashAdvancePendingTransferDto> PendingTransfers,
    IReadOnlyList<CashAdvanceTransferAllocationDto> TransferAllocations,
    IReadOnlyList<CashAdvanceHistoryDto> History,
    IReadOnlyList<CashAdvanceAttachmentDto> Attachments,
    IReadOnlyList<CashAdvanceReceiptDetailDto> ReceiptDetails,
    IReadOnlyList<PettyCashReceiptDetailDto> PettyCashReceiptDetails,
    IReadOnlyList<PettyCashTransportationDetailDto> PettyCashTransportationDetails,
    CashierReceiptDto? AcknowledgementReceipt)
{
    public string PrintToken { get; init; } = string.Empty;
    public int? PayeeUserId { get; init; }
}

public sealed class SubmitCashAdvanceLiquidationFormRequest
{
    public int? UserId { get; set; }
    public decimal AmountSpent { get; set; }
    public string? Notes { get; set; }
    public string? ReceiptDetailsJson { get; set; }
    public string? PettyCashReceiptDetailsJson { get; set; }
    public string? PettyCashTransportationDetailsJson { get; set; }
    public bool ReplaceExistingAttachments { get; set; }
    public List<IFormFile>? Attachments { get; set; }
}

public sealed record StoredAttachmentInput(
    string OriginalFileName,
    string StoredFileName,
    string RelativePath,
    string ContentType,
    long FileSizeBytes);

public sealed record SubmitCashAdvanceLiquidationRequest(
    int? UserId,
    decimal AmountSpent,
    string? Notes,
    string? ReceiptDetailsJson,
    string? PettyCashReceiptDetailsJson,
    string? PettyCashTransportationDetailsJson,
    bool ReplaceExistingAttachments,
    IReadOnlyList<StoredAttachmentInput> Attachments);

public sealed record WorkflowDecisionRequest(
    int UserId,
    bool Approved,
    string? Notes,
    string? RfpDecision = null,
    int? CompanyId = null,
    decimal? ReturnedAmount = null);

public sealed class CreatePettyCashFormRequest
{
    public int? CompanyId { get; set; }
    public string? RequestType { get; set; }
    public int RequestorUserId { get; set; }
    public int CustodianUserId { get; set; }
    public decimal Amount { get; set; }
    public string? Purpose { get; set; }
    public string? PettyCashReceiptDetailsJson { get; set; }
    public string? PettyCashTransportationDetailsJson { get; set; }
    public List<IFormFile>? Attachments { get; set; }
}

public sealed record CreatePettyCashRequest(
    string RequestType,
    int RequestorUserId,
    int CustodianUserId,
    decimal Amount,
    string Purpose,
    string ReceiptDetailsJson,
    string TransportationDetailsJson,
    int? CompanyId = null);

public sealed record CreatePettyCashReplenishmentRequest(
    int CustodianUserId,
    decimal Amount,
    string? Notes);

public sealed record SubmitPettyCashReplenishmentCvRequest(
    int CustodianUserId,
    string? CvNumber);

public sealed class SubmitRfpAttachmentFormRequest
{
    public string? Notes { get; set; }
    public List<IFormFile>? Attachments { get; set; }
}

public sealed record SubmitRfpAttachmentRequest(
    string? Notes,
    IReadOnlyList<StoredAttachmentInput> Attachments);

public sealed record TransferCashAdvanceRequest(
    int ToUserId,
    decimal Amount,
    bool TransferWholeRequest,
    string? Notes);

public sealed record TransferAcknowledgementRequest(
    int ReceiverUserId,
    bool Accepted,
    string? Notes,
    string? TransferId);

public sealed class CashierReceiptFormRequest
{
    public int CashierUserId { get; set; }
    public string ReceiptNumber { get; set; } = string.Empty;
    public IFormFile? Attachment { get; set; }
    public IFormFile? DepositSlip { get; set; }
    public DateTime? DepositDate { get; set; }
    public decimal? DepositAmount { get; set; }
    public string? DepositoryBank { get; set; }
    public string? Notes { get; set; }
}

public sealed record CashierReceiptRequest(
    int CashierUserId,
    string ReceiptNumber,
    StoredAttachmentInput? AcknowledgementReceipt,
    StoredAttachmentInput? DepositSlip,
    DateTime? DepositDate,
    decimal? DepositAmount,
    string? DepositoryBank,
    string? Notes);

public sealed class CustodianReceiptFormRequest
{
    public int CustodianUserId { get; set; }
    public string ReceiptNumber { get; set; } = string.Empty;
    public string? Notes { get; set; }
}

public sealed record CustodianReceiptRequest(
    int CustodianUserId,
    string ReceiptNumber,
    string? Notes);

public sealed record StoredFileDownload(
    int Id,
    string OriginalFileName,
    string RelativePath,
    string ContentType);
