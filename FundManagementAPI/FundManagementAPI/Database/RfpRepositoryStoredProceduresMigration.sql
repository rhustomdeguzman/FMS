USE FMS;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_GetDecisionState
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    SELECT StatusId, AmountSpent, COALESCE(LiquidationBaseAmount, Amount) AS BaseAmount, ExcessAmount
    FROM dbo.FMS_CashAdvanceRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE CashAdvanceRequestId = @Id
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_SetCompany
    @CompanyId int,
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
        IF NOT EXISTS (SELECT 1 FROM dbo.vw_FMS_Company WHERE ID = @CompanyId)
            THROW 51160, 'Select a valid RFP company.', 1;
        UPDATE dbo.FMS_CashAdvanceRequests SET CompanyID = @CompanyId
        WHERE CashAdvanceRequestId = @Id AND CompanyID IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_GetRequestContext
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    SELECT r.RequestNumber, r.Purpose, r.CompanyID, u.DisplayName,
           fr.RequestorID AS FineReportRequestorId,
           COALESCE(department.DepartmentCode, TRY_CONVERT(int, h.ReqGroup)) AS RequestGroup,
           h.PayeeCode, h.PayeeName, h.Recommendation, h.Attachment_Folder
    FROM dbo.FMS_CashAdvanceRequests r
    INNER JOIN dbo.FMS_AppUsers u ON u.UserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId)
    OUTER APPLY (
        SELECT TOP (1) f.RequestorID, f.DeptGroup
        FROM FineReport.dbo.FineReport_RFP_Requestor f
        WHERE LTRIM(RTRIM(f.EmailAddress)) COLLATE DATABASE_DEFAULT = LTRIM(RTRIM(u.Email))
        ORDER BY f.RequestorID
    ) fr
    OUTER APPLY (
        SELECT MIN(a.DepartmentCode) AS DepartmentCode
        FROM dbo.FMS_ApproverDepartments a
        WHERE a.UserID = u.UserId
          AND EXISTS (SELECT 1 FROM FineReport.dbo.FineReport_RFP_Approvers approver WHERE approver.ID = a.DepartmentCode)
        HAVING COUNT(DISTINCT a.DepartmentCode) = 1
    ) department
    OUTER APPLY (
        SELECT TOP (1) source.PayeeCode, source.PayeeName, source.Recommendation, source.Attachment_Folder, source.ReqGroup
        FROM FineReport.dbo.New_ORFP_Hdr source
        WHERE CONVERT(nvarchar(50), source.RF_Number) = r.RfpRequestNumber
           OR CONVERT(nvarchar(50), source.RF_Number) = r.RequestNumber
           OR source.RF_Number = (
               SELECT TRY_CONVERT(int, original.RfpRequestNumber)
               FROM dbo.FMS_CashAdvanceRequests original
               WHERE original.CashAdvanceRequestId = r.OriginalCashAdvanceRequestId
           )
        ORDER BY source.RF_Number DESC
    ) h
    WHERE r.CashAdvanceRequestId = @Id
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_GetRequestDetails
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    SELECT Capex, CostCenter, Project, BillRef, IntRef, Amount, Remarks
    FROM (
        SELECT 0 AS RowType, CashAdvanceRequestDtlId AS RowId,
               ExpenseTypeCode AS Capex, ProfitCenterCode AS CostCenter, ProjectCode AS Project,
               InvoiceRef AS BillRef, '' AS IntRef, Amount, [Description] AS Remarks
        FROM dbo.FMS_CashAdvanceRequests_Dtl WHERE CashAdvanceRequestId = @Id
        UNION ALL
        SELECT 1, PettyCashReceiptDetailId, '3', CostCenter, '', OrNumber, '', Amount,
               NatureOfExpense
        FROM dbo.FMS_PettyCashReceiptDetails WHERE CashAdvanceRequestId = @Id
          AND NOT EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests_Dtl WHERE CashAdvanceRequestId = @Id)
        UNION ALL
        SELECT 2, PettyCashTransportationDetailId, '3', '', '', '', '', Amount,
               CONCAT([Description], ' (', FromLocation, ' to ', ToLocation, ')')
        FROM dbo.FMS_PettyCashTransportationDetails WHERE CashAdvanceRequestId = @Id
          AND NOT EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests_Dtl WHERE CashAdvanceRequestId = @Id)
    ) rows
    ORDER BY RowType, RowId
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_LinkRequest
    @Number nvarchar(50),
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    UPDATE dbo.FMS_CashAdvanceRequests SET RfpRequestNumber = @Number WHERE CashAdvanceRequestId = @Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_DepartmentDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL,
    @RfpDecision nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    EXEC dbo.sp_CashAdvanceRequests_DepartmentDecision @CashAdvanceRequestId = @CashAdvanceRequestId, @ApproverUserId = @ApproverUserId, @Approved = @Approved, @Notes = @Notes, @RfpDecision = @RfpDecision;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rfp_SaveData
    @Mode varchar(100),
    @RequestorID varchar(100) = NULL,
    @CompanyID varchar(100) = NULL,
    @PayeeCode varchar(100) = NULL,
    @PayeeName varchar(200) = NULL,
    @AltPayeeCode varchar(100) = NULL,
    @PurOfDisbursement varchar(500) = NULL,
    @TypeOfExpense varchar(100) = NULL,
    @Payment_Terms varchar(100) = NULL,
    @TotalAmount varchar(100) = NULL,
    @Recommendation varchar(100) = NULL,
    @ReqGrp varchar(100) = NULL,
    @AttachFolder varchar(100) = NULL,
    @Request_Type varchar(100) = NULL,
    @RFNumber varchar(100) = NULL,
    @Capex varchar(100) = NULL,
    @CostCenter varchar(10) = NULL,
    @Project varchar(20) = NULL,
    @BillRef varchar(500) = NULL,
    @Intref varchar(200) = NULL,
    @Amount money = NULL,
    @Remarks varchar(1000) = NULL,
    @DtlCount int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET XACT_ABORT ON;
    -- The caller owns the transaction across the header, details and request link.
    IF @@TRANCOUNT = 0
        THROW 51161, 'RFP saving requires an active transaction.', 1;

    IF @Mode = 'header'
    BEGIN
        -- The legacy procedure uses MAX(RF_Number) + 1 and returns MAX(RF_Number).
        -- Keep the table lock until the caller commits all details.
        DECLARE @LastRfNumber int;
        SELECT @LastRfNumber = MAX(RF_Number)
        FROM FineReport.dbo.New_ORFP_Hdr WITH (TABLOCKX, HOLDLOCK);
    END;

    IF @Mode = 'header'
    BEGIN
        EXEC FineReport.dbo.sp_ORFP_SavingData
            @Mode = @Mode,
            @RequestorID = @RequestorID,
            @CompanyID = @CompanyID,
            @PayeeCode = @PayeeCode,
            @PayeeName = @PayeeName,
            @AltPayeeCode = @AltPayeeCode,
            @PurOfDisbursement = @PurOfDisbursement,
            @TypeOfExpense = @TypeOfExpense,
            @Payment_Terms = @Payment_Terms,
            @TotalAmount = @TotalAmount,
            @Recommendation = @Recommendation,
            @ReqGrp = @ReqGrp,
            @AttachFolder = @AttachFolder,
            @Request_Type = @Request_Type;
    END
    ELSE
    BEGIN
        EXEC FineReport.dbo.sp_ORFP_SavingData
            @Mode = @Mode,
            @RFNumber = @RFNumber,
            @Capex = @Capex,
            @CostCenter = @CostCenter,
            @Project = @Project,
            @BillRef = @BillRef,
            @Intref = @Intref,
            @Amount = @Amount,
            @Remarks = @Remarks,
            @DtlCount = @DtlCount;
    END;
END;
GO
