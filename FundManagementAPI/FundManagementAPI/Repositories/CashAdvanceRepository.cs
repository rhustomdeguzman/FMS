using System.Text.Json;
using FundManagementAPI.Data;
using FundManagementAPI.Models;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Repositories;

public sealed class CashAdvanceRepository : ICashAdvanceRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly ISqlDataAccess _db;
    private readonly RfpRepository _rfpRepository;

    public CashAdvanceRepository(ISqlDataAccess db, RfpRepository rfpRepository)
    {
        _db = db;
        _rfpRepository = rfpRepository;
    }

    public Task<string?> GetReceiptDocumentNumberAsync(CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "GeneralLedgerNew..spDocumentControl",
            new[] { SqlParameters.NVarChar("@Mode", "GetDocNo", 50), SqlParameters.NVarChar("@DocType", "R", 1) },
            reader => Convert.ToString(reader["DocNo"], System.Globalization.CultureInfo.InvariantCulture),
            cancellationToken);

    private static SqlParameter[] CompanyParameters(int companyId) =>
        new[] { SqlParameters.Int("@CompanyId", companyId) };

    public Task<IReadOnlyList<AppUserDto>> GetAppUsersAsync(bool includeInactive, CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_AppUsers_GetAll",
            new[] { SqlParameters.Bit("@IncludeInactive", includeInactive) },
            MapAppUser,
            cancellationToken);

    public Task<LoginResponseDto?> LoginAsync(LoginRequest request, CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_Auth_Login",
            new[]
            {
                SqlParameters.NVarChar("@Username", request.Username, 50),
                SqlParameters.NVarChar("@Password", request.Password, 200)
            },
            reader => new LoginResponseDto(MapAppUser(reader), "Login successful."),
            cancellationToken);

    public Task<AppUserDto?> CreateAppUserAsync(CreateAppUserRequest request, CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_AppUsers_Create",
            new[]
            {
                SqlParameters.Int("@AdminUserId", request.AdminUserId),
                SqlParameters.NVarChar("@Username", request.Username, 50),
                SqlParameters.NVarChar("@Password", request.Password, 200),
                SqlParameters.NVarChar("@DisplayName", request.DisplayName, 150),
                SqlParameters.NVarChar("@Department", request.Department, 100),
                SqlParameters.NVarChar("@Role", request.Role, 50),
                SqlParameters.NVarChar("@Title", request.Title, 100),
                SqlParameters.NullableDecimal("@PettyCashFundAmount", request.PettyCashFundAmount)
            },
            MapAppUser,
            cancellationToken);

    public Task<AppUserDto?> UpdateAppUserAsync(
        int userId,
        UpdateAppUserRequest request,
        CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_AppUsers_Update",
            new[]
            {
                SqlParameters.Int("@AdminUserId", request.AdminUserId),
                SqlParameters.Int("@UserId", userId),
                SqlParameters.NVarChar("@Username", request.Username, 50),
                SqlParameters.NVarChar("@DisplayName", request.DisplayName, 150),
                SqlParameters.NVarChar("@Department", request.Department, 100),
                SqlParameters.NVarChar("@Role", request.Role, 50),
                SqlParameters.NVarChar("@Title", request.Title, 100),
                SqlParameters.NVarChar("@Password", request.Password, 200),
                SqlParameters.NullableDecimal("@PettyCashFundAmount", request.PettyCashFundAmount)
            },
            MapAppUser,
            cancellationToken);

    public Task<AppUserDto?> UpdateCustodianFundAsync(
        int userId,
        UpdateCustodianFundRequest request,
        CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_AppUsers_UpdateCustodianFund",
            new[]
            {
                SqlParameters.Int("@AdminUserId", request.AdminUserId),
                SqlParameters.Int("@UserId", userId),
                SqlParameters.Decimal("@PettyCashFundAmount", request.PettyCashFundAmount)
            },
            MapAppUser,
            cancellationToken);

    public Task<IReadOnlyList<DepartmentCustodianAssignmentDto>> GetDepartmentCustodianAssignmentsAsync(
        CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_DepartmentCustodians_GetAll",
            Array.Empty<SqlParameter>(),
            MapDepartmentCustodianAssignment,
            cancellationToken);

    public Task<DepartmentCustodianAssignmentDto?> UpdateDepartmentCustodianAssignmentAsync(
        int departmentCode,
        UpdateDepartmentCustodianRequest request,
        CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_DepartmentCustodians_Assign",
            new[]
            {
                SqlParameters.Int("@AdminUserId", request.AdminUserId),
                SqlParameters.Int("@DepartmentCode", departmentCode),
                SqlParameters.Int("@CustodianUserId", request.CustodianUserId)
            },
            MapDepartmentCustodianAssignment,
            cancellationToken);

    public Task<IReadOnlyList<CashAdvanceWorkflowRequestDto>> GetCashAdvanceRequestsAsync(
        int userId,
        string role,
        string department,
        CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_CashAdvanceRequests_GetForUser",
            new[]
            {
                SqlParameters.Int("@UserId", userId),
                SqlParameters.NVarChar("@Role", ToRequestAccessRole(role), 50),
                SqlParameters.NVarChar("@Department", department, 100)
            },
            MapCashAdvanceWorkflowRequest,
            cancellationToken);

    public Task<IReadOnlyList<CashAdvanceWorkflowRequestDto>> GetApprovalHistoryRequestsAsync(
        int userId,
        string role,
        string department,
        CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_CashAdvanceRequests_GetForUser",
            new[]
            {
                SqlParameters.Int("@UserId", userId),
                SqlParameters.NVarChar("@Role", ToRequestAccessRole(role), 50),
                SqlParameters.NVarChar("@Department", department, 100),
                SqlParameters.Bit("@ProcessedOnly", !IsAdminRole(role))
            },
            MapCashAdvanceWorkflowRequest,
            cancellationToken);

    public Task<IReadOnlyList<BusinessPartnerDto>> GetBusinessPartnersAsync(
        int? companyId,
        CancellationToken cancellationToken) =>
        companyId is > 0
            ? _db.QueryAsync(
                "dbo.sp_BusinessPartners_GetByCompany",
                CompanyParameters(companyId.Value),
                MapBusinessPartner,
                cancellationToken)
            : _db.QueryAsync(
                "dbo.sp_OtherBusinessPartners_GetAll",
                Array.Empty<SqlParameter>(),
                MapBusinessPartner,
                cancellationToken);

    public Task<IReadOnlyList<CompanyDto>> GetCompaniesAsync(CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_Companies_GetAll",
            Array.Empty<SqlParameter>(),
            MapCompany,
            cancellationToken);

    public Task<IReadOnlyList<ProjectDto>> GetProjectsAsync(
        int? companyId,
        CancellationToken cancellationToken) =>
        companyId is > 0
            ? _db.QueryAsync(
                "dbo.sp_Projects_GetByCompany",
                CompanyParameters(companyId.Value),
                MapProject,
                cancellationToken)
            : _db.QueryAsync(
                "dbo.sp_Projects_GetAll",
                Array.Empty<SqlParameter>(),
                MapProject,
                cancellationToken);

    public Task<IReadOnlyList<ProfitCenterDto>> GetProfitCentersAsync(
        int? companyId,
        CancellationToken cancellationToken) =>
        companyId is > 0
            ? _db.QueryAsync(
                "dbo.sp_ProfitCenters_GetByCompany",
                CompanyParameters(companyId.Value),
                MapProfitCenter,
                cancellationToken)
            : _db.QueryAsync(
                "dbo.sp_ProfitCenters_GetAll",
                Array.Empty<SqlParameter>(),
                MapProfitCenter,
                cancellationToken);

    public Task<IReadOnlyList<CostCenterDto>> GetCostCentersAsync(
        int companyId,
        CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_CostCenters_GetByCompany",
            CompanyParameters(companyId),
            MapCostCenter,
            cancellationToken);

    public Task<IReadOnlyList<ExpenseTypeDto>> GetExpenseTypesAsync(CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_ExpenseTypes_GetAll",
            Array.Empty<SqlParameter>(),
            MapExpenseType,
            cancellationToken);

    public Task<IReadOnlyList<AccountingReportRowDto>> GetAccountingReportRowsAsync(
        int userId,
        DateTime? fromDate,
        DateTime? toDate,
        CancellationToken cancellationToken) =>
        _db.QueryAsync(
            "dbo.sp_CashAdvanceRequests_GetAccountingReport",
            new[]
            {
                SqlParameters.Int("@UserId", userId),
                SqlParameters.NullableDateTime("@FromDate", fromDate),
                SqlParameters.NullableDateTime("@ToDate", toDate)
            },
            MapAccountingReportRow,
            cancellationToken);

    public Task SubmitCashAdvanceLiquidationAsync(
        int cashAdvanceRequestId,
        SubmitCashAdvanceLiquidationRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_SubmitLiquidation",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.NullableInt("@LiquidatingUserId", request.UserId),
                SqlParameters.Decimal("@AmountSpent", request.AmountSpent),
                SqlParameters.NVarChar("@Notes", request.Notes, -1),
                SqlParameters.NVarChar("@AttachmentsJson", JsonSerializer.Serialize(request.Attachments), -1),
                SqlParameters.NVarChar("@ReceiptDetailsJson", request.ReceiptDetailsJson, -1),
                SqlParameters.NVarChar("@PettyCashReceiptDetailsJson", request.PettyCashReceiptDetailsJson, -1),
                SqlParameters.NVarChar("@PettyCashTransportationDetailsJson", request.PettyCashTransportationDetailsJson, -1),
                SqlParameters.Bit("@ReplaceExistingAttachments", request.ReplaceExistingAttachments)
            },
            cancellationToken);

    public Task SubmitCashAdvanceRfpAttachmentAsync(
        int cashAdvanceRequestId,
        SubmitRfpAttachmentRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_SubmitRfpAttachment",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.NVarChar("@Notes", request.Notes, -1),
                SqlParameters.NVarChar("@AttachmentsJson", JsonSerializer.Serialize(request.Attachments), -1)
            },
            cancellationToken);

    public Task TransferCashAdvanceAsync(
        int cashAdvanceRequestId,
        TransferCashAdvanceRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_Transfer",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@ToUserId", request.ToUserId),
                SqlParameters.Decimal("@Amount", request.Amount),
                SqlParameters.Bit("@TransferWholeRequest", request.TransferWholeRequest),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task RespondToCashAdvanceTransferAsync(
        int cashAdvanceRequestId,
        TransferAcknowledgementRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_TransferResponse",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@ReceiverUserId", request.ReceiverUserId),
                SqlParameters.Bit("@Accepted", request.Accepted),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000),
                SqlParameters.NullableInt("@TransferId", ParseTransferId(request.TransferId))
            },
            cancellationToken);

    public Task DecideCashAdvanceDepartmentAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken) =>
        _rfpRepository.DecideDepartmentAsync(cashAdvanceRequestId, request, cancellationToken);

    public async Task<int> CreatePettyCashRequestAsync(
        CreatePettyCashRequest request,
        CancellationToken cancellationToken)
    {
        var requestId = await _db.QuerySingleAsync(
            "dbo.sp_PettyCashRequests_Create",
            new[]
            {
                SqlParameters.NVarChar("@RequestType", request.RequestType, 50),
                SqlParameters.Int("@RequestorUserId", request.RequestorUserId),
                SqlParameters.Int("@CustodianUserId", request.CustodianUserId),
                SqlParameters.Decimal("@Amount", request.Amount),
                SqlParameters.NVarChar("@Purpose", request.Purpose, 500),
                SqlParameters.NVarChar("@ReceiptDetailsJson", request.ReceiptDetailsJson, -1),
                SqlParameters.NVarChar("@TransportationDetailsJson", request.TransportationDetailsJson, -1),
                SqlParameters.NullableInt("@CompanyId", request.CompanyId)
            },
            reader => reader.GetInt32(0),
            cancellationToken);

        return requestId;
    }

    public Task AddCashAdvanceAttachmentsAsync(
        int cashAdvanceRequestId,
        IReadOnlyList<StoredAttachmentInput> attachments,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_AddAttachments",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.NVarChar("@AttachmentsJson", JsonSerializer.Serialize(attachments), -1)
            },
            cancellationToken);

    public Task DecidePettyCashCustodianAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_PettyCashRequests_CustodianDecision",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@CustodianUserId", request.UserId),
                SqlParameters.Bit("@Approved", request.Approved),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000),
                SqlParameters.NullableDecimal("@ReturnedAmount", request.ReturnedAmount)
            },
            cancellationToken);

    public Task CreatePettyCashReplenishmentAsync(
        CreatePettyCashReplenishmentRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_PettyCashRequests_CreateReplenishment",
            new[]
            {
                SqlParameters.Int("@CustodianUserId", request.CustodianUserId),
                SqlParameters.Decimal("@Amount", request.Amount),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task SubmitPettyCashReplenishmentCvAsync(
        int cashAdvanceRequestId,
        SubmitPettyCashReplenishmentCvRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_PettyCashRequests_SubmitReplenishmentCv",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@CustodianUserId", request.CustodianUserId),
                SqlParameters.NVarChar("@CvNumber", request.CvNumber, 50)
            },
            cancellationToken);

    public Task CreateCashierReceiptAsync(
        int cashAdvanceRequestId,
        CashierReceiptRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_CashierCreateReceipt",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@CashierUserId", request.CashierUserId),
                SqlParameters.NVarChar("@ReceiptNumber", request.ReceiptNumber, 50),
                SqlParameters.NVarChar("@AttachmentFileName", request.AcknowledgementReceipt?.OriginalFileName, 260),
                SqlParameters.NVarChar("@AttachmentStoredFileName", request.AcknowledgementReceipt?.StoredFileName, 260),
                SqlParameters.NVarChar("@AttachmentRelativePath", request.AcknowledgementReceipt?.RelativePath, 500),
                SqlParameters.NVarChar("@AttachmentContentType", request.AcknowledgementReceipt?.ContentType, 100),
                SqlParameters.BigInt("@AttachmentFileSizeBytes", request.AcknowledgementReceipt?.FileSizeBytes),
                SqlParameters.NVarChar("@DepositSlipFileName", request.DepositSlip?.OriginalFileName, 260),
                SqlParameters.NVarChar("@DepositSlipStoredFileName", request.DepositSlip?.StoredFileName, 260),
                SqlParameters.NVarChar("@DepositSlipRelativePath", request.DepositSlip?.RelativePath, 500),
                SqlParameters.NVarChar("@DepositSlipContentType", request.DepositSlip?.ContentType, 100),
                SqlParameters.BigInt("@DepositSlipFileSizeBytes", request.DepositSlip?.FileSizeBytes),
                SqlParameters.NullableDateTime("@DepositDate", request.DepositDate),
                SqlParameters.NullableDecimal("@DepositAmount", request.DepositAmount),
                SqlParameters.NVarChar("@DepositoryBank", request.DepositoryBank, 150),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task CreateCustodianReceiptAsync(
        int cashAdvanceRequestId,
        CustodianReceiptRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_PettyCashRequests_CustodianCreateReceipt",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@CustodianUserId", request.CustodianUserId),
                SqlParameters.NVarChar("@ReceiptNumber", request.ReceiptNumber, 50),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task CloseCashierLiquidationAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_CashierCloseLiquidation",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@CashierUserId", request.UserId),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task DecideCashAdvanceAccountingAsync(
        int cashAdvanceRequestId,
        WorkflowDecisionRequest request,
        CancellationToken cancellationToken) =>
        _db.ExecuteAsync(
            "dbo.sp_CashAdvanceRequests_AccountingDecision",
            new[]
            {
                SqlParameters.Int("@CashAdvanceRequestId", cashAdvanceRequestId),
                SqlParameters.Int("@ApproverUserId", request.UserId),
                SqlParameters.Bit("@Approved", request.Approved),
                SqlParameters.NVarChar("@Notes", request.Notes, 1000)
            },
            cancellationToken);

    public Task<StoredFileDownload?> GetCashAdvanceAttachmentAsync(int attachmentId, CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_CashAdvanceAttachments_GetById",
            new[] { SqlParameters.Int("@AttachmentId", attachmentId) },
            MapStoredFileDownload,
            cancellationToken);

    public Task<StoredFileDownload?> GetCashierReceiptAttachmentAsync(int receiptId, CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_CashAdvanceAcknowledgementReceipts_GetAttachmentById",
            new[] { SqlParameters.Int("@ReceiptId", receiptId) },
            MapStoredFileDownload,
            cancellationToken);

    public Task<StoredFileDownload?> GetCashierDepositSlipAttachmentAsync(int receiptId, CancellationToken cancellationToken) =>
        _db.QuerySingleAsync(
            "dbo.sp_CashAdvanceAcknowledgementReceipts_GetDepositSlipById",
            new[] { SqlParameters.Int("@ReceiptId", receiptId) },
            MapStoredFileDownload,
            cancellationToken);

    private static AppUserDto MapAppUser(SqlDataReader reader) =>
        new(
            GetInt32(reader, "UserId"),
            GetString(reader, "Username"),
            GetString(reader, "DisplayName"),
            GetString(reader, "Department"),
            GetString(reader, "Role"),
            GetString(reader, "Title"),
            GetBoolean(reader, "IsActive"),
            GetNullableDecimalIfPresent(reader, "PettyCashFundAmount"),
            GetNullableInt32IfPresent(reader, "RoleCode"),
            GetNullableInt32IfPresent(reader, "DepartmentCode"),
            ParseInt32List(GetNullableStringIfPresent(reader, "DepartmentGroups")));

    private static DepartmentCustodianAssignmentDto MapDepartmentCustodianAssignment(SqlDataReader reader) =>
        new(
            GetInt32(reader, "DepartmentCode"),
            GetString(reader, "DepartmentName"),
            GetNullableInt32IfPresent(reader, "CustodianUserId"),
            GetNullableStringIfPresent(reader, "CustodianName"),
            GetNullableStringIfPresent(reader, "CustodianDepartment"),
            GetNullableDecimalIfPresent(reader, "CustodianFundAmount"));

    private static BusinessPartnerDto MapBusinessPartner(SqlDataReader reader) =>
        new(
            GetNullableStringIfPresent(reader, "Code") ?? GetString(reader, "BP_Code"),
            GetNullableStringIfPresent(reader, "Name") ?? GetString(reader, "BP_Name"));

    private static CompanyDto MapCompany(SqlDataReader reader) =>
        new(
            GetNullableInt32IfPresent(reader, "CompanyId"),
            GetString(reader, "Name"));

    private static ProjectDto MapProject(SqlDataReader reader) =>
        new(
            GetNullableStringIfPresent(reader, "Code") ?? GetString(reader, "ProjCode"),
            GetNullableStringIfPresent(reader, "Name") ?? GetString(reader, "ProjName"));

    private static ProfitCenterDto MapProfitCenter(SqlDataReader reader) =>
        new(
            GetNullableStringIfPresent(reader, "Code") ?? GetString(reader, "OcrCode"),
            GetNullableStringIfPresent(reader, "Name") ?? GetString(reader, "OcrName"));

    private static CostCenterDto MapCostCenter(SqlDataReader reader) =>
        new(
            GetNullableStringIfPresent(reader, "Code") ?? GetString(reader, "OcrCode"),
            GetNullableStringIfPresent(reader, "Name") ?? GetString(reader, "OcrName"));

    private static ExpenseTypeDto MapExpenseType(SqlDataReader reader) =>
        new(
            GetString(reader, "Expense_Code"),
            GetString(reader, "Expense_Name"));

    private static AccountingReportRowDto MapAccountingReportRow(SqlDataReader reader) =>
        new(
            GetString(reader, "RequestNumber"),
            GetString(reader, "VendorCode"),
            GetString(reader, "Description"),
            GetString(reader, "ProjectCode"),
            GetString(reader, "ProfitCenterCode"),
            GetDecimal(reader, "Amount"),
            GetString(reader, "InvoiceRef"),
            GetString(reader, "ExpenseTypeCode"));

    internal static CashAdvanceWorkflowRequestDto MapCashAdvanceWorkflowRequest(SqlDataReader reader) =>
        new(
            GetInt32(reader, "CashAdvanceRequestId"),
            GetNullableInt32(reader, "OriginalCashAdvanceRequestId"),
            GetString(reader, "RequestNumber"),
            GetNullableStringIfPresent(reader, "RfpRequestNumber"),
            GetNullableStringIfPresent(reader, "CvNumber"),
            GetNullableInt32IfPresent(reader, "CompanyID"),
            GetNullableStringIfPresent(reader, "CompanyCode"),
            GetNullableStringIfPresent(reader, "RequestType") ?? "cash_advance",
            GetNullableStringIfPresent(reader, "SourceSystem") ?? "RFP System",
            GetDecimal(reader, "Amount"),
            GetDecimal(reader, "RemainingAmount"),
            GetNullableDecimal(reader, "AmountSpent"),
            GetNullableDecimal(reader, "ReturnAmount"),
            GetNullableDecimal(reader, "ExcessAmount"),
            GetString(reader, "Purpose"),
            GetString(reader, "Department"),
            GetString(reader, "Status"),
            GetInt32(reader, "RequestorUserId"),
            GetString(reader, "RequestorName"),
            GetNullableStringIfPresent(reader, "RequestorDepartmentApproverName"),
            GetNullableInt32IfPresent(reader, "CustodianUserId"),
            GetNullableStringIfPresent(reader, "CustodianName"),
            GetNullableStringIfPresent(reader, "CustodianDepartment"),
            GetInt32(reader, "CurrentOwnerUserId"),
            GetString(reader, "CurrentOwnerName"),
            GetString(reader, "CurrentOwnerDepartment"),
            GetNullableInt32(reader, "PendingTransferId"),
            GetNullableInt32(reader, "PendingTransferFromUserId"),
            GetNullableString(reader, "PendingTransferFromName"),
            GetNullableString(reader, "PendingTransferFromDepartment"),
            GetNullableInt32(reader, "PendingTransferToUserId"),
            GetNullableString(reader, "PendingTransferToName"),
            GetNullableString(reader, "PendingTransferToDepartment"),
            GetNullableDecimal(reader, "PendingTransferAmount"),
            GetNullableBoolean(reader, "PendingTransferIsWholeRequest"),
            GetNullableString(reader, "PendingTransferNotes"),
            GetNullableDateTime(reader, "PendingTransferRequestedAt"),
            GetDateTime(reader, "AuditDate"),
            GetNullableDateTimeIfPresent(reader, "DueDate"),
            GetNullableDateTime(reader, "LiquidatedAt"),
            GetNullableDateTime(reader, "UpdatedAt"),
            DeserializeList<CashAdvancePendingTransferDto>(GetNullableStringIfPresent(reader, "PendingTransfersJson")),
            DeserializeList<CashAdvanceTransferAllocationDto>(GetNullableStringIfPresent(reader, "TransferAllocationsJson")),
            DeserializeList<CashAdvanceHistoryDto>(GetNullableStringIfPresent(reader, "HistoryJson")),
            DeserializeList<CashAdvanceAttachmentDto>(GetNullableStringIfPresent(reader, "AttachmentsJson")),
            DeserializeList<CashAdvanceReceiptDetailDto>(GetNullableStringIfPresent(reader, "ReceiptDetailsJson")),
            DeserializeList<PettyCashReceiptDetailDto>(GetNullableStringIfPresent(reader, "PettyCashReceiptDetailsJson")),
            DeserializeList<PettyCashTransportationDetailDto>(GetNullableStringIfPresent(reader, "PettyCashTransportationDetailsJson")),
            DeserializeObject<CashierReceiptDto>(GetNullableStringIfPresent(reader, "AcknowledgementReceiptJson")))
        {
            PayeeUserId = GetNullableInt32IfPresent(reader, "PayeeUserId")
        };

    private static StoredFileDownload MapStoredFileDownload(SqlDataReader reader) =>
        new(
            GetInt32(reader, "Id"),
            GetString(reader, "OriginalFileName"),
            GetString(reader, "RelativePath"),
            GetString(reader, "ContentType"));

    private static IReadOnlyList<T> DeserializeList<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return Array.Empty<T>();
        }

        return JsonSerializer.Deserialize<IReadOnlyList<T>>(json, JsonOptions) ?? Array.Empty<T>();
    }

    private static T? DeserializeObject<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return default;
        }

        return JsonSerializer.Deserialize<T>(json, JsonOptions);
    }

    private static int? ParseTransferId(string? transferId) =>
        int.TryParse(transferId, out var parsedTransferId) ? parsedTransferId : null;

    private static IReadOnlyList<int> ParseInt32List(string? values) =>
        string.IsNullOrWhiteSpace(values)
            ? Array.Empty<int>()
            : values.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(value => int.TryParse(value, out var parsedValue) ? parsedValue : (int?)null)
                .Where(value => value.HasValue)
                .Select(value => value!.Value)
                .Distinct()
                .ToArray();

    private static bool IsAdminRole(string role) =>
        string.Equals(role, "admin", StringComparison.OrdinalIgnoreCase);

    private static string ToRequestAccessRole(string role) =>
        IsAdminRole(role) ? "accounting" : role;

    private static int GetInt32(SqlDataReader reader, string name) =>
        reader.GetInt32(reader.GetOrdinal(name));

    private static int? GetNullableInt32(SqlDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    }

    private static string GetString(SqlDataReader reader, string name) =>
        reader.GetString(reader.GetOrdinal(name));

    private static string? GetNullableString(SqlDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    private static string? GetNullableStringIfPresent(SqlDataReader reader, string name)
    {
        for (var ordinal = 0; ordinal < reader.FieldCount; ordinal++)
        {
            if (string.Equals(reader.GetName(ordinal), name, StringComparison.OrdinalIgnoreCase))
            {
                return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
            }
        }

        return null;
    }

    private static int? GetNullableInt32IfPresent(SqlDataReader reader, string name)
    {
        for (var ordinal = 0; ordinal < reader.FieldCount; ordinal++)
        {
            if (string.Equals(reader.GetName(ordinal), name, StringComparison.OrdinalIgnoreCase))
            {
                return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
            }
        }

        return null;
    }

    private static decimal GetDecimal(SqlDataReader reader, string name) =>
        reader.GetDecimal(reader.GetOrdinal(name));

    private static decimal? GetNullableDecimal(SqlDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
    }

    private static decimal? GetNullableDecimalIfPresent(SqlDataReader reader, string name)
    {
        for (var ordinal = 0; ordinal < reader.FieldCount; ordinal++)
        {
            if (string.Equals(reader.GetName(ordinal), name, StringComparison.OrdinalIgnoreCase))
            {
                return reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
            }
        }

        return null;
    }

    private static bool GetBoolean(SqlDataReader reader, string name) =>
        reader.GetBoolean(reader.GetOrdinal(name));

    private static bool? GetNullableBoolean(SqlDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetBoolean(ordinal);
    }

    private static DateTime GetDateTime(SqlDataReader reader, string name) =>
        reader.GetDateTime(reader.GetOrdinal(name));

    private static DateTime? GetNullableDateTime(SqlDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    private static DateTime? GetNullableDateTimeIfPresent(SqlDataReader reader, string name)
    {
        for (var ordinal = 0; ordinal < reader.FieldCount; ordinal++)
        {
            if (string.Equals(reader.GetName(ordinal), name, StringComparison.OrdinalIgnoreCase))
            {
                return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
            }
        }

        return null;
    }
}
