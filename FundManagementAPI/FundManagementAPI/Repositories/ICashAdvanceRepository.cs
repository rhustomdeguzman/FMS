using FundManagementAPI.Models;

namespace FundManagementAPI.Repositories;

public interface ICashAdvanceRepository
{
    Task<string?> GetReceiptDocumentNumberAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<AppUserDto>> GetAppUsersAsync(bool includeInactive, CancellationToken cancellationToken);
    Task<LoginResponseDto?> LoginAsync(LoginRequest request, CancellationToken cancellationToken);
    Task<AppUserDto?> CreateAppUserAsync(CreateAppUserRequest request, CancellationToken cancellationToken);
    Task<AppUserDto?> UpdateAppUserAsync(int userId, UpdateAppUserRequest request, CancellationToken cancellationToken);
    Task<AppUserDto?> UpdateCustodianFundAsync(int userId, UpdateCustodianFundRequest request, CancellationToken cancellationToken);
    Task<IReadOnlyList<DepartmentCustodianAssignmentDto>> GetDepartmentCustodianAssignmentsAsync(
        CancellationToken cancellationToken);
    Task<DepartmentCustodianAssignmentDto?> UpdateDepartmentCustodianAssignmentAsync(
        int departmentCode,
        UpdateDepartmentCustodianRequest request,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<CashAdvanceWorkflowRequestDto>> GetCashAdvanceRequestsAsync(
        int userId,
        string role,
        string department,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<CashAdvanceWorkflowRequestDto>> GetApprovalHistoryRequestsAsync(
        int userId,
        string role,
        string department,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<BusinessPartnerDto>> GetBusinessPartnersAsync(int? companyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<CompanyDto>> GetCompaniesAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<ProjectDto>> GetProjectsAsync(int? companyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<ProfitCenterDto>> GetProfitCentersAsync(int? companyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<CostCenterDto>> GetCostCentersAsync(int companyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<ExpenseTypeDto>> GetExpenseTypesAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<AccountingReportRowDto>> GetAccountingReportRowsAsync(
        int userId,
        DateTime? fromDate,
        DateTime? toDate,
        CancellationToken cancellationToken);

    Task SubmitCashAdvanceLiquidationAsync(
        int cashAdvanceRequestId,
        SubmitCashAdvanceLiquidationRequest request,
        CancellationToken cancellationToken);

    Task SubmitCashAdvanceRfpAttachmentAsync(
        int cashAdvanceRequestId,
        SubmitRfpAttachmentRequest request,
        CancellationToken cancellationToken);

    Task TransferCashAdvanceAsync(
        int cashAdvanceRequestId,
        TransferCashAdvanceRequest request,
        CancellationToken cancellationToken);

    Task RespondToCashAdvanceTransferAsync(
        int cashAdvanceRequestId,
        TransferAcknowledgementRequest request,
        CancellationToken cancellationToken);

    Task DecideCashAdvanceDepartmentAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken);

    Task<int> CreatePettyCashRequestAsync(
        CreatePettyCashRequest request,
        CancellationToken cancellationToken);

    Task AddCashAdvanceAttachmentsAsync(
        int cashAdvanceRequestId,
        IReadOnlyList<StoredAttachmentInput> attachments,
        CancellationToken cancellationToken);

    Task DecidePettyCashCustodianAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken);

    Task CreatePettyCashReplenishmentAsync(
        CreatePettyCashReplenishmentRequest request,
        CancellationToken cancellationToken);

    Task SubmitPettyCashReplenishmentCvAsync(
        int cashAdvanceRequestId,
        SubmitPettyCashReplenishmentCvRequest request,
        CancellationToken cancellationToken);

    Task CreateCashierReceiptAsync(
        int cashAdvanceRequestId,
        CashierReceiptRequest request,
        CancellationToken cancellationToken);

    Task CreateCustodianReceiptAsync(
        int cashAdvanceRequestId,
        CustodianReceiptRequest request,
        CancellationToken cancellationToken);

    Task CloseCashierLiquidationAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken);

    Task DecideCashAdvanceAccountingAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken);

    Task<StoredFileDownload?> GetCashAdvanceAttachmentAsync(int attachmentId, CancellationToken cancellationToken);

    Task<StoredFileDownload?> GetCashierReceiptAttachmentAsync(int receiptId, CancellationToken cancellationToken);

    Task<StoredFileDownload?> GetCashierDepositSlipAttachmentAsync(int receiptId, CancellationToken cancellationToken);
}
