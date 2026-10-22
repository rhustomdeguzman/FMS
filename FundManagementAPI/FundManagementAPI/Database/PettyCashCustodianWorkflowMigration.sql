SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH(N'dbo.FMS_AppUsers', N'PettyCashFundAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_AppUsers ADD PettyCashFundAmount decimal(19,4) NULL;
END
GO

DECLARE @RoleAliases TABLE
(
    RoleAlias nvarchar(100) NOT NULL PRIMARY KEY,
    RoleCode nvarchar(50) NOT NULL
);

INSERT INTO @RoleAliases (RoleAlias, RoleCode)
VALUES
    (N'admin', N'admin'),
    (N'administrator', N'admin'),
    (N'system admin', N'admin'),
    (N'system administrator', N'admin'),
    (N'requestor', N'requestor'),
    (N'requester', N'requestor'),
    (N'requestor user', N'requestor'),
    (N'requester user', N'requestor'),
    (N'department head', N'department_head'),
    (N'department approver', N'department_head'),
    (N'dept head', N'department_head'),
    (N'depthead', N'department_head'),
    (N'approver', N'department_head'),
    (N'accounting', N'accounting'),
    (N'accounting reviewer', N'accounting'),
    (N'accounts payable', N'accounting'),
    (N'account payable', N'accounting'),
    (N'ap', N'accounting'),
    (N'cashier', N'cashier'),
    (N'custodian', N'custodian'),
    (N'petty cash custodian', N'custodian');

DECLARE @RoleTitles TABLE
(
    RoleCode nvarchar(50) NOT NULL PRIMARY KEY,
    Title nvarchar(100) NOT NULL
);

INSERT INTO @RoleTitles (RoleCode, Title)
VALUES
    (N'admin', N'Administrator'),
    (N'requestor', N'Requestor'),
    (N'department_head', N'Department Head'),
    (N'accounting', N'Accounting Reviewer'),
    (N'cashier', N'Cashier'),
    (N'custodian', N'Petty Cash Custodian');

IF EXISTS
(
    SELECT 1
    FROM dbo.FMS_AppUsers userRow
    CROSS APPLY
    (
        SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
    ) normalized
    LEFT JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
    WHERE roleAlias.RoleCode IS NULL
)
BEGIN
    THROW 51051, 'One or more FMS_AppUsers roles could not be normalized.', 1;
END

UPDATE userRow
SET Role = roleAlias.RoleCode,
    Title = roleTitle.Title,
    PettyCashFundAmount = CASE
        WHEN roleAlias.RoleCode = N'custodian' THEN COALESCE(NULLIF(userRow.PettyCashFundAmount, 0), 20000)
        ELSE NULL
    END
FROM dbo.FMS_AppUsers userRow
CROSS APPLY
(
    SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
) normalized
INNER JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
INNER JOIN @RoleTitles roleTitle ON roleTitle.RoleCode = roleAlias.RoleCode;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_AppUsers_Role')
BEGIN
    ALTER TABLE dbo.FMS_AppUsers DROP CONSTRAINT CK_AppUsers_Role;
END
GO

ALTER TABLE dbo.FMS_AppUsers
ADD CONSTRAINT CK_AppUsers_Role CHECK (Role IN ('admin', 'requestor', 'department_head', 'accounting', 'cashier', 'custodian'));
GO

DECLARE @DepartmentCustodians TABLE
(
    Username nvarchar(50) NOT NULL PRIMARY KEY,
    DisplayName nvarchar(200) NOT NULL,
    Department nvarchar(100) NOT NULL,
    PettyCashFundAmount decimal(19,4) NOT NULL
);

INSERT INTO @DepartmentCustodians (Username, DisplayName, Department, PettyCashFundAmount)
VALUES
    (N'custodian', N'Petty Cash Custodian', N'Accounting', 20000),
    (N'mis.custodian', N'MIS Petty Cash Custodian', N'MIS', 20000),
    (N'it.custodian', N'IT Petty Cash Custodian', N'IT', 20000),
    (N'its.custodian', N'IT & Systems Petty Cash Custodian', N'IT & Systems', 20000),
    (N'hr.custodian', N'HR Petty Cash Custodian', N'HR', 20000),
    (N'eng.custodian', N'Engineering Petty Cash Custodian', N'Engineering', 20000),
    (N'am.custodian', N'Accounts Management Petty Cash Custodian', N'Accounts Management', 20000);

UPDATE target
SET DisplayName = source.DisplayName,
    Department = source.Department,
    Role = N'custodian',
    Title = N'Petty Cash Custodian',
    PettyCashFundAmount = source.PettyCashFundAmount,
    IsActive = 1
FROM dbo.FMS_AppUsers target
INNER JOIN @DepartmentCustodians source ON source.Username = target.Username;

INSERT INTO dbo.FMS_AppUsers (Username, DisplayName, Department, Role, Title, PasswordHash, PettyCashFundAmount)
SELECT source.Username,
       source.DisplayName,
       source.Department,
       N'custodian',
       N'Petty Cash Custodian',
       HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123')),
       source.PettyCashFundAmount
FROM @DepartmentCustodians source
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FMS_AppUsers existing
    WHERE existing.Username = source.Username
);
GO

MERGE dbo.FMS_CashAdvanceStatuses AS target
USING
(
    VALUES
        (12, N'pending_custodian_approval', N'Pending Custodian Approval', 12),
        (13, N'pending_custodian_liquidation_review', N'Pending Custodian Liquidation Review', 13),
        (14, N'pending_replenishment', N'Pending Replenishment', 14),
        (15, N'replenished', N'Replenished', 15)
) AS source(StatusId, StatusCode, DisplayName, SortOrder)
ON target.StatusId = source.StatusId
WHEN MATCHED THEN
    UPDATE SET StatusCode = source.StatusCode,
               DisplayName = source.DisplayName,
               SortOrder = source.SortOrder,
               IsActive = 1
WHEN NOT MATCHED THEN
    INSERT (StatusId, StatusCode, DisplayName, SortOrder)
    VALUES (source.StatusId, source.StatusCode, source.DisplayName, source.SortOrder);
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RequestType') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RequestType nvarchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CompanyCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CompanyCode nvarchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CompanyID') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CompanyID int NULL;
END
GO

UPDATE dbo.FMS_CashAdvanceRequests
SET RequestType = N'cash_advance'
WHERE RequestType IS NULL;
GO

ALTER TABLE dbo.FMS_CashAdvanceRequests ALTER COLUMN RequestType nvarchar(50) NOT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_RequestType')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT CK_CashAdvanceRequests_RequestType;
END
GO

ALTER TABLE dbo.FMS_CashAdvanceRequests
ADD CONSTRAINT CK_CashAdvanceRequests_RequestType
CHECK (RequestType IN ('cash_advance', 'petty_cash', 'petty_cash_advance', 'petty_cash_replenishment'));
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CustodianUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CustodianUserId int NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CvNumber') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CvNumber nvarchar(50) NULL;
END
GO

UPDATE dbo.FMS_CashAdvanceRequests
SET StatusId = 14
WHERE RequestType = N'petty_cash_replenishment'
  AND StatusId = 10
  AND CvNumber IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_Custodian')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_Custodian FOREIGN KEY (CustodianUserId) REFERENCES dbo.FMS_AppUsers(UserId);
END
GO

IF OBJECT_ID(N'dbo.FMS_PettyCashReceiptDetails', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_PettyCashReceiptDetails
    (
        PettyCashReceiptDetailId int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_FMS_PettyCashReceiptDetails PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        OrNumber nvarchar(100) NOT NULL,
        Company nvarchar(200) NOT NULL,
        Tin nvarchar(100) NOT NULL,
        Address nvarchar(500) NOT NULL,
        NatureOfExpense nvarchar(300) NOT NULL,
        CostCenter nvarchar(100) NOT NULL,
        TaxType nvarchar(20) NULL,
        Amount decimal(19,4) NOT NULL,
        OrDate date NOT NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_FMS_PettyCashReceiptDetails_AuditDate DEFAULT GETDATE(),
        CONSTRAINT FK_FMS_PettyCashReceiptDetails_Request
            FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT CK_FMS_PettyCashReceiptDetails_Amount CHECK (Amount > 0)
    );
END
GO

IF COL_LENGTH(N'dbo.FMS_PettyCashReceiptDetails', N'TaxType') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_PettyCashReceiptDetails ADD TaxType nvarchar(20) NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FMS_PettyCashReceiptDetails_TaxType')
BEGIN
    ALTER TABLE dbo.FMS_PettyCashReceiptDetails DROP CONSTRAINT CK_FMS_PettyCashReceiptDetails_TaxType;
END
GO

IF COL_LENGTH(N'dbo.FMS_PettyCashReceiptDetails', N'TaxType') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_PettyCashReceiptDetails ALTER COLUMN TaxType nvarchar(20) NULL;
END
GO

IF OBJECT_ID(N'dbo.FMS_PettyCashTransportationDetails', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_PettyCashTransportationDetails
    (
        PettyCashTransportationDetailId int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_FMS_PettyCashTransportationDetails PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        [Description] nvarchar(300) NOT NULL,
        FromLocation nvarchar(200) NOT NULL,
        ToLocation nvarchar(200) NOT NULL,
        TransactionDate date NOT NULL,
        Amount decimal(19,4) NOT NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_FMS_PettyCashTransportationDetails_AuditDate DEFAULT GETDATE(),
        CONSTRAINT FK_FMS_PettyCashTransportationDetails_Request
            FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT CK_FMS_PettyCashTransportationDetails_Amount CHECK (Amount > 0)
    );
END
GO

IF COL_LENGTH(N'dbo.FMS_PettyCashTransportationDetails', N'TransactionDate') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_PettyCashTransportationDetails ADD TransactionDate date NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_PettyCashTransportationDetails', N'TransactionDate') IS NOT NULL
BEGIN
    UPDATE dbo.FMS_PettyCashTransportationDetails
    SET TransactionDate = CONVERT(date, AuditDate)
    WHERE TransactionDate IS NULL;

    ALTER TABLE dbo.FMS_PettyCashTransportationDetails ALTER COLUMN TransactionDate date NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_GetForUser
    @UserId int,
    @Role nvarchar(50),
    @Department nvarchar(100),
    @ProcessedOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.CashAdvanceRequestId,
           r.OriginalCashAdvanceRequestId,
           r.RequestNumber,
           r.RfpRequestNumber,
           r.CvNumber,
           r.CompanyID,
           r.CompanyCode,
           r.RequestType,
           CASE
               WHEN r.RequestType IN (N'petty_cash', N'petty_cash_advance') AND r.CustodianUserId IS NOT NULL THEN N'Petty Cash'
               ELSE N'RFP System'
           END AS SourceSystem,
           r.Amount,
           COALESCE(r.RemainingAmount, CASE WHEN r.StatusId IN (0, 7) THEN r.Amount ELSE 0 END) AS RemainingAmount,
           r.AmountSpent,
           r.ReturnAmount,
           r.ExcessAmount,
           r.Purpose,
           r.Department,
           requestStatus.StatusCode AS Status,
           r.RequestorUserId,
           u.DisplayName AS RequestorName,
           requestorDepartmentApprover.DisplayName AS RequestorDepartmentApproverName,
           r.CustodianUserId,
           custodian.DisplayName AS CustodianName,
           custodian.Department AS CustodianDepartment,
           COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) AS CurrentOwnerUserId,
           cu.DisplayName AS CurrentOwnerName,
           cu.Department AS CurrentOwnerDepartment,
           pendingTransfer.TransferId AS PendingTransferId,
           pendingTransfer.FromUserId AS PendingTransferFromUserId,
           pendingFrom.DisplayName AS PendingTransferFromName,
           pendingFrom.Department AS PendingTransferFromDepartment,
           pendingTransfer.ToUserId AS PendingTransferToUserId,
           pendingTo.DisplayName AS PendingTransferToName,
           pendingTo.Department AS PendingTransferToDepartment,
           pendingTransfer.TransferAmount AS PendingTransferAmount,
           pendingTransfer.IsWholeRequest AS PendingTransferIsWholeRequest,
           pendingTransfer.Notes AS PendingTransferNotes,
           pendingTransfer.RequestedAt AS PendingTransferRequestedAt,
           r.AuditDate,
           r.DueDate,
           r.LiquidatedAt,
           r.UpdatedAt,
           ISNULL((
               SELECT t.TransferId AS pendingTransferId,
                      t.FromUserId AS pendingTransferFromUserId,
                      transferFrom.DisplayName AS pendingTransferFromName,
                      transferFrom.Department AS pendingTransferFromDepartment,
                      t.ToUserId AS pendingTransferToUserId,
                      transferTo.DisplayName AS pendingTransferToName,
                      transferTo.Department AS pendingTransferToDepartment,
                      t.TransferAmount AS pendingTransferAmount,
                      t.IsWholeRequest AS pendingTransferIsWholeRequest,
                      t.Notes AS pendingTransferNotes,
                      t.RequestedAt AS pendingTransferRequestedAt
               FROM dbo.FMS_CashAdvanceTransfers t
               INNER JOIN dbo.FMS_AppUsers transferFrom ON transferFrom.UserId = t.FromUserId
               INNER JOIN dbo.FMS_AppUsers transferTo ON transferTo.UserId = t.ToUserId
               WHERE t.CashAdvanceRequestId = r.CashAdvanceRequestId
                 AND t.Status = 'pending'
               ORDER BY t.RequestedAt, t.TransferId
               FOR JSON PATH
           ), N'[]') AS PendingTransfersJson,
           ISNULL((
               SELECT t.TransferId AS transferId,
                      t.FromUserId AS transferFromUserId,
                      transferFrom.DisplayName AS transferFromName,
                      transferFrom.Department AS transferFromDepartment,
                      t.ToUserId AS transferToUserId,
                      transferTo.DisplayName AS transferToName,
                      transferTo.Department AS transferToDepartment,
                      t.TransferAmount AS transferAmount,
                      t.IsWholeRequest AS transferIsWholeRequest,
                      t.Status AS transferStatus,
                      t.Notes AS transferNotes,
                      t.ResponseNotes AS transferResponseNotes,
                      t.RequestedAt AS transferRequestedAt,
                      t.RespondedAt AS transferRespondedAt
               FROM dbo.FMS_CashAdvanceTransfers t
               INNER JOIN dbo.FMS_AppUsers transferFrom ON transferFrom.UserId = t.FromUserId
               INNER JOIN dbo.FMS_AppUsers transferTo ON transferTo.UserId = t.ToUserId
               WHERE t.CashAdvanceRequestId = r.CashAdvanceRequestId
                 AND t.Status IN ('pending', 'acknowledged')
               ORDER BY t.RequestedAt, t.TransferId
               FOR JSON PATH
           ), N'[]') AS TransferAllocationsJson,
           ISNULL((
               SELECT h.HistoryId AS historyId,
                      h.Action AS action,
                      h.ActorUserId AS actorUserId,
                      actor.DisplayName AS actorName,
                      actor.Department AS actorDepartment,
                      h.Amount AS amount,
                      h.Notes AS notes,
                      h.AuditDate AS auditDate
               FROM dbo.FMS_CashAdvanceHistory h
               LEFT JOIN dbo.FMS_AppUsers actor ON actor.UserId = h.ActorUserId
               WHERE h.CashAdvanceRequestId = r.CashAdvanceRequestId
               ORDER BY h.AuditDate, h.HistoryId
               FOR JSON PATH
           ), N'[]') AS HistoryJson,
           ISNULL((
               SELECT a.AttachmentId AS attachmentId,
                      COALESCE(a.OriginalFileName, a.FileName) AS fileName,
                      COALESCE(a.ContentType, N'application/octet-stream') AS contentType,
                      COALESCE(a.FileSizeBytes, 0) AS fileSizeBytes
               FROM dbo.FMS_CashAdvanceAttachments a
               WHERE a.CashAdvanceRequestId = r.CashAdvanceRequestId
               ORDER BY a.UploadedAt, a.AttachmentId
               FOR JSON PATH
            ), N'[]') AS AttachmentsJson,
            ISNULL((
                SELECT d.CashAdvanceRequestDtlId AS receiptDetailId,
                       d.VendorCode AS vendorCode,
                       COALESCE(vendorInfo.VendorName, d.VendorCode, N'') AS vendor,
                       d.[Description] AS description,
                       d.ProjectCode AS projectCode,
                       COALESCE(projectInfo.ProjName, d.ProjectCode, N'') AS project,
                       d.ProfitCenterCode AS profitCenterCode,
                       COALESCE(profitCenterInfo.OcrName, d.ProfitCenterCode, N'') AS profitCenter,
                       d.Amount AS amount,
                       d.InvoiceRef AS invoiceRef,
                       d.ExpenseTypeCode AS expenseTypeCode,
                       COALESCE(expenseTypeInfo.ExpenseName, d.ExpenseTypeCode, N'') AS expenseType,
                       d.AuditDate AS auditDate
                FROM dbo.FMS_CashAdvanceRequests_Dtl d
                OUTER APPLY
                (
                    SELECT TOP (1) VendorName
                    FROM
                    (
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee_CCI
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee_AJVR
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee_ALC
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee_CMC
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'') AS VendorName
                        FROM FineReport..vwVendorPayee_CHI
                    ) vendorRows
                    WHERE vendorRows.VendorCode = d.VendorCode
                      AND vendorRows.VendorName IS NOT NULL
                    ORDER BY vendorRows.VendorName
                ) vendorInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT)), N'') AS ExpenseName
                    FROM dbo.vw_FMS_ExpenseType expenseTypeView
                    WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), expenseTypeView.Code) COLLATE DATABASE_DEFAULT)), N'') = d.ExpenseTypeCode
                    ORDER BY LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT))
                ) expenseTypeInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(projectView.ProjName COLLATE DATABASE_DEFAULT)), N'') AS ProjName
                    FROM FineReport..vwProjects projectView
                    WHERE NULLIF(LTRIM(RTRIM(projectView.ProjCode COLLATE DATABASE_DEFAULT)), N'') = d.ProjectCode
                    ORDER BY LTRIM(RTRIM(projectView.ProjName COLLATE DATABASE_DEFAULT))
                ) projectInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT)), N'') AS OcrName
                    FROM FineReport..vwProfitCenters profitCenterView
                    WHERE NULLIF(LTRIM(RTRIM(profitCenterView.OcrCode COLLATE DATABASE_DEFAULT)), N'') = d.ProfitCenterCode
                      AND profitCenterView.OcrCode COLLATE DATABASE_DEFAULT LIKE N'OD-DP%'
                    ORDER BY LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT))
                ) profitCenterInfo
                WHERE d.CashAdvanceRequestId = r.CashAdvanceRequestId
                ORDER BY d.CashAdvanceRequestDtlId
                FOR JSON PATH
            ), N'[]') AS ReceiptDetailsJson,
            ISNULL((
                SELECT pc.PettyCashReceiptDetailId AS pettyCashReceiptDetailId,
                       pc.OrNumber AS orNumber,
                       pc.Company AS company,
                       pc.Tin AS tin,
                       pc.Address AS address,
                       pc.NatureOfExpense AS natureOfExpenseCode,
                       COALESCE(pettyExpenseTypeInfo.ExpenseName, pc.NatureOfExpense, N'') AS natureOfExpense,
                       pc.CostCenter AS costCenterCode,
                       COALESCE(pettyProfitCenterInfo.OcrName, pc.CostCenter, N'') AS costCenter,
                       pc.TaxType AS taxType,
                       pc.Amount AS amount,
                       pc.OrDate AS orDate,
                       pc.AuditDate AS auditDate
                FROM dbo.FMS_PettyCashReceiptDetails pc
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT)), N'') AS ExpenseName
                    FROM dbo.vw_FMS_ExpenseType expenseTypeView
                    WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), expenseTypeView.Code) COLLATE DATABASE_DEFAULT)), N'') = pc.NatureOfExpense
                    ORDER BY LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT))
                ) pettyExpenseTypeInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT)), N'') AS OcrName
                    FROM FineReport..vwProfitCenters profitCenterView
                    WHERE NULLIF(LTRIM(RTRIM(profitCenterView.OcrCode COLLATE DATABASE_DEFAULT)), N'') = pc.CostCenter
                    ORDER BY LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT))
                ) pettyProfitCenterInfo
                WHERE pc.CashAdvanceRequestId = r.CashAdvanceRequestId
                ORDER BY pc.PettyCashReceiptDetailId
                FOR JSON PATH
            ), N'[]') AS PettyCashReceiptDetailsJson,
            ISNULL((
                SELECT transportation.PettyCashTransportationDetailId AS pettyCashTransportationDetailId,
                       transportation.[Description] AS description,
                       transportation.FromLocation AS [from],
                       transportation.ToLocation AS [to],
                       transportation.TransactionDate AS transactionDate,
                       transportation.Amount AS amount,
                       transportation.AuditDate AS auditDate
                FROM dbo.FMS_PettyCashTransportationDetails transportation
                WHERE transportation.CashAdvanceRequestId = r.CashAdvanceRequestId
                ORDER BY transportation.PettyCashTransportationDetailId
                FOR JSON PATH
            ), N'[]') AS PettyCashTransportationDetailsJson,
            (
                SELECT TOP (1)
                       receipt.ReceiptId AS receiptId,
                      receipt.ReceiptNumber AS receiptNumber,
                      receipt.ReturnAmount AS returnAmount,
                      receipt.AttachmentFileName AS attachmentFileName,
                      receipt.AttachmentContentType AS attachmentContentType,
                      receipt.AttachmentFileSizeBytes AS attachmentFileSizeBytes,
                      receipt.DepositSlipFileName AS depositSlipFileName,
                      receipt.DepositSlipContentType AS depositSlipContentType,
                      receipt.DepositSlipFileSizeBytes AS depositSlipFileSizeBytes,
                      receipt.DepositDate AS depositDate,
                      receipt.DepositAmount AS depositAmount,
                      receipt.DepositoryBank AS depositoryBank,
                      receipt.AuditDate AS auditDate
               FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
               WHERE receipt.CashAdvanceRequestId = r.CashAdvanceRequestId
               ORDER BY receipt.AuditDate DESC, receipt.ReceiptId DESC
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
           ) AS AcknowledgementReceiptJson
    FROM dbo.FMS_CashAdvanceRequests r
    INNER JOIN dbo.FMS_CashAdvanceStatuses requestStatus ON requestStatus.StatusId = r.StatusId
    INNER JOIN dbo.FMS_AppUsers u ON u.UserId = r.RequestorUserId
    INNER JOIN dbo.FMS_AppUsers cu ON cu.UserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId)
    LEFT JOIN dbo.FMS_AppUsers custodian ON custodian.UserId = r.CustodianUserId
    OUTER APPLY
    (
        SELECT TOP (1) departmentApprover.DisplayName
        FROM dbo.FMS_AppUsers departmentApprover
        WHERE departmentApprover.Role = 'department_head'
          AND departmentApprover.IsActive = 1
          AND LOWER(LTRIM(RTRIM(departmentApprover.Department))) = LOWER(LTRIM(RTRIM(u.Department)))
        ORDER BY departmentApprover.DisplayName
    ) requestorDepartmentApprover
    OUTER APPLY
    (
        SELECT TOP (1)
               t.TransferId,
               t.FromUserId,
               t.ToUserId,
               t.TransferAmount,
               t.IsWholeRequest,
               t.Notes,
               t.RequestedAt
        FROM dbo.FMS_CashAdvanceTransfers t
        WHERE t.CashAdvanceRequestId = r.CashAdvanceRequestId
          AND t.Status = 'pending'
        ORDER BY t.RequestedAt DESC, t.TransferId DESC
    ) pendingTransfer
    LEFT JOIN dbo.FMS_AppUsers pendingFrom ON pendingFrom.UserId = pendingTransfer.FromUserId
    LEFT JOIN dbo.FMS_AppUsers pendingTo ON pendingTo.UserId = pendingTransfer.ToUserId
    WHERE
        (
            @ProcessedOnly = 1
            AND EXISTS
            (
                SELECT 1
                FROM dbo.FMS_CashAdvanceHistory processedHistory
                WHERE processedHistory.CashAdvanceRequestId = r.CashAdvanceRequestId
                  AND processedHistory.ActorUserId = @UserId
                  AND
                  (
                      (@Role = 'department_head' AND processedHistory.Action IN ('approved_by_department_head', 'rfp_created', 'rfp_waived', 'returned', 'rejected'))
                      OR (@Role = 'accounting' AND processedHistory.Action IN ('approved_by_accounting', 'returned'))
                      OR (@Role = 'cashier' AND processedHistory.Action IN ('acknowledged', 'fully_liquidated'))
                      OR (@Role = 'custodian' AND processedHistory.Action IN ('petty_cash_released', 'approved_by_custodian', 'petty_cash_replenishment_created', 'petty_cash_replenished', 'rejected', 'returned'))
                  )
            )
        )
        OR
        (
            @ProcessedOnly = 0
            AND
            (
                EXISTS
                (
                    SELECT 1
                    FROM dbo.FMS_CashAdvanceTransfers accessTransfer
                    WHERE accessTransfer.CashAdvanceRequestId = r.CashAdvanceRequestId
                      AND accessTransfer.Status = 'pending'
                      AND accessTransfer.ToUserId = @UserId
                )
                OR
                (@Role = 'requestor' AND (COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId OR r.RequestorUserId = @UserId))
                OR (@Role = 'department_head' AND COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId)
                OR (@Role = 'department_head' AND r.Department = @Department AND r.StatusId IN (1, 5))
                OR (@Role = 'department_head' AND r.Department = @Department AND COALESCE(r.RequestType, N'cash_advance') = N'cash_advance' AND r.StatusId IN (0, 7))
                OR (@Role = 'custodian' AND (r.CustodianUserId = @UserId OR COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId))
                OR (@Role = 'cashier' AND
                    (
                        r.StatusId IN (2, 3)
                        OR EXISTS
                        (
                            SELECT 1
                            FROM dbo.FMS_CashAdvanceAcknowledgementReceipts cashierReceipt
                            WHERE cashierReceipt.CashAdvanceRequestId = r.CashAdvanceRequestId
                        )
                    ))
                OR (@Role = 'accounting')
            )
        )
    ORDER BY r.AuditDate DESC, r.CashAdvanceRequestId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_SubmitLiquidation
    @CashAdvanceRequestId int,
    @LiquidatingUserId int = NULL,
    @AmountSpent decimal(19,4),
    @Notes nvarchar(max) = NULL,
    @AttachmentsJson nvarchar(max) = NULL,
    @ReceiptDetailsJson nvarchar(max) = NULL,
    @PettyCashReceiptDetailsJson nvarchar(max) = NULL,
    @PettyCashTransportationDetailsJson nvarchar(max) = NULL,
    @ReplaceExistingAttachments bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentOwnerUserId int;
    DECLARE @ActorUserId int;
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @RequestDepartment nvarchar(100);
    DECLARE @RequestType nvarchar(50);
    DECLARE @CustodianUserId int;
    DECLARE @LiquidatingUserRoleCode int;
    DECLARE @ShouldClaimFullCustody bit = 0;
    DECLARE @UsesPettyCashDetails bit = 0;

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @LiquidationBaseAmount = COALESCE(RemainingAmount, Amount),
           @RequestDepartment = Department,
           @RequestType = RequestType,
           @CustodianUserId = CustodianUserId
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    SELECT @LiquidatingUserRoleCode = RoleCode
    FROM dbo.FMS_AppUsers
    WHERE UserId = @LiquidatingUserId
      AND IsActive = 1;

    SET @ActorUserId = COALESCE(@LiquidatingUserId, @CurrentOwnerUserId);

    IF @LiquidatingUserId IS NOT NULL AND @LiquidatingUserId <> @CurrentOwnerUserId
    BEGIN
        IF @LiquidatingUserRoleCode = 3
           AND COALESCE(@RequestType, N'cash_advance') = N'cash_advance'
           AND EXISTS
           (
               SELECT 1
               FROM dbo.FMS_ApproverDepartments assignment
               INNER JOIN dbo.FMS_Departments department
                   ON department.DepartmentCode = assignment.DepartmentCode
               WHERE assignment.UserID = @LiquidatingUserId
                 AND LOWER(LTRIM(RTRIM(department.DepartmentName))) = LOWER(LTRIM(RTRIM(COALESCE(@RequestDepartment, N''))))
           )
        BEGIN
            SET @ShouldClaimFullCustody = 1;
        END
        ELSE
        BEGIN
            RAISERROR('Only the current owner or department approver can submit liquidation.', 16, 1);
            RETURN;
        END
    END

    SET @UsesPettyCashDetails = CASE
        WHEN @RequestType IN (N'petty_cash', N'petty_cash_advance') AND @CustodianUserId IS NOT NULL THEN 1
        ELSE 0
    END;

    IF @UsesPettyCashDetails = 1 AND @AmountSpent > @LiquidationBaseAmount
    BEGIN
        RAISERROR('Petty cash liquidation cannot exceed the released amount.', 16, 1);
        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET AmountSpent = @AmountSpent,
        CurrentOwnerUserId = CASE WHEN @ShouldClaimFullCustody = 1 THEN @LiquidatingUserId ELSE CurrentOwnerUserId END,
        RemainingAmount = 0,
        LiquidationBaseAmount = @LiquidationBaseAmount,
        ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END,
        ExcessAmount = CASE
            WHEN @UsesPettyCashDetails = 1 THEN 0
            WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount
            ELSE 0
        END,
        LiquidationNotes = @Notes,
        RfpRequestNumber = NULL,
        RfpDecision = NULL,
        RfpWaiveReason = NULL,
        StatusId = 1,
        LiquidatedAt = GETDATE(),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId IN (0, 7)
      AND @LiquidationBaseAmount > 0
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.FMS_CashAdvanceTransfers pendingTransfer
          WHERE pendingTransfer.CashAdvanceRequestId = @CashAdvanceRequestId
            AND pendingTransfer.Status = 'pending'
      );

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Cash advance request is not ready for liquidation or has a pending transfer acknowledgement.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'liquidation_submitted', @ActorUserId, @AmountSpent, @Notes);

    DELETE FROM dbo.FMS_CashAdvanceRequests_Dtl
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    IF ISJSON(@ReceiptDetailsJson) = 1
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceRequests_Dtl
            (CashAdvanceRequestId, VendorCode, [Description], ProjectCode, ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode)
        SELECT @CashAdvanceRequestId,
               LTRIM(RTRIM(VendorCode)),
               LTRIM(RTRIM([Description])),
               ProjectInfo.ProjectCode,
               ProfitCenterInfo.ProfitCenterCode,
               Amount,
               LTRIM(RTRIM(InvoiceRef)),
               ExpenseTypeInfo.ExpenseTypeCode
        FROM OPENJSON(@ReceiptDetailsJson)
        WITH
        (
            VendorCode varchar(50) '$.VendorCode',
            Vendor nvarchar(200) '$.Vendor',
            [Description] nvarchar(500) '$.Description',
            ProjectCode nvarchar(20) '$.ProjectCode',
            Project nvarchar(200) '$.Project',
            ProfitCenterCode nvarchar(8) '$.ProfitCenterCode',
            ProfitCenter nvarchar(200) '$.ProfitCenter',
            Amount decimal(19,4) '$.Amount',
            InvoiceRef nvarchar(100) '$.InvoiceRef',
            ExpenseTypeCode varchar(50) '$.ExpenseTypeCode',
            ExpenseType nvarchar(200) '$.ExpenseType'
        ) ReceiptDetail
        OUTER APPLY
        (
            SELECT TOP (1) NULLIF(LTRIM(RTRIM(projectView.ProjCode COLLATE DATABASE_DEFAULT)), N'') AS ProjectCode
            FROM FineReport..vwProjects projectView
            WHERE NULLIF(LTRIM(RTRIM(projectView.ProjCode COLLATE DATABASE_DEFAULT)), N'') = NULLIF(LTRIM(RTRIM(ReceiptDetail.ProjectCode)), N'')
               OR (
                   NULLIF(LTRIM(RTRIM(ReceiptDetail.ProjectCode)), N'') IS NULL
                   AND NULLIF(LTRIM(RTRIM(projectView.ProjName COLLATE DATABASE_DEFAULT)), N'') = NULLIF(LTRIM(RTRIM(ReceiptDetail.Project)), N'')
               )
            ORDER BY LTRIM(RTRIM(projectView.ProjName COLLATE DATABASE_DEFAULT))
        ) ProjectInfo
        OUTER APPLY
        (
            SELECT TOP (1) NULLIF(LTRIM(RTRIM(profitCenterView.OcrCode COLLATE DATABASE_DEFAULT)), N'') AS ProfitCenterCode
            FROM FineReport..vwProfitCenters profitCenterView
            WHERE profitCenterView.OcrCode COLLATE DATABASE_DEFAULT LIKE N'OD-DP%'
              AND
              (
                  NULLIF(LTRIM(RTRIM(profitCenterView.OcrCode COLLATE DATABASE_DEFAULT)), N'') = NULLIF(LTRIM(RTRIM(ReceiptDetail.ProfitCenterCode)), N'')
                  OR
                  (
                      NULLIF(LTRIM(RTRIM(ReceiptDetail.ProfitCenterCode)), N'') IS NULL
                      AND NULLIF(LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT)), N'') = NULLIF(LTRIM(RTRIM(ReceiptDetail.ProfitCenter)), N'')
                  )
              )
            ORDER BY LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT))
        ) ProfitCenterInfo
        OUTER APPLY
        (
            SELECT TOP (1) LTRIM(RTRIM(Expense_Code)) AS ExpenseTypeCode
            FROM dbo.FMS_ExpenseType expenseType
            WHERE LTRIM(RTRIM(expenseType.Expense_Code)) = NULLIF(LTRIM(RTRIM(ReceiptDetail.ExpenseTypeCode)), '')
               OR
               (
                   NULLIF(LTRIM(RTRIM(ReceiptDetail.ExpenseTypeCode)), '') IS NULL
                   AND LTRIM(RTRIM(expenseType.Expense_Name)) = NULLIF(LTRIM(RTRIM(ReceiptDetail.ExpenseType)), '')
               )
            ORDER BY LTRIM(RTRIM(expenseType.Expense_Name))
        ) ExpenseTypeInfo
        WHERE VendorCode IS NOT NULL AND LTRIM(RTRIM(VendorCode)) <> ''
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FMS_OtherBP_CLI bp
              WHERE bp.BP_Code = VendorCode
          )
          AND [Description] IS NOT NULL AND LTRIM(RTRIM([Description])) <> ''
          AND ProjectInfo.ProjectCode IS NOT NULL
          AND ProfitCenterInfo.ProfitCenterCode IS NOT NULL
          AND Amount > 0
          AND InvoiceRef IS NOT NULL AND LTRIM(RTRIM(InvoiceRef)) <> ''
          AND ExpenseTypeInfo.ExpenseTypeCode IS NOT NULL;
    END

    IF ISJSON(@AttachmentsJson) = 1
    BEGIN
        IF @ReplaceExistingAttachments = 1
           AND EXISTS
           (
               SELECT 1
               FROM OPENJSON(@AttachmentsJson)
               WITH (OriginalFileName nvarchar(260) '$.OriginalFileName')
               WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> ''
           )
        BEGIN
            DELETE FROM dbo.FMS_CashAdvanceAttachments
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
        END

        INSERT INTO dbo.FMS_CashAdvanceAttachments
            (CashAdvanceRequestId, FileName, OriginalFileName, StoredFileName, RelativePath, ContentType, FileSizeBytes)
        SELECT @CashAdvanceRequestId,
               OriginalFileName,
               OriginalFileName,
               StoredFileName,
               RelativePath,
               ContentType,
               FileSizeBytes
        FROM OPENJSON(@AttachmentsJson)
        WITH
        (
            OriginalFileName nvarchar(260) '$.OriginalFileName',
            StoredFileName nvarchar(260) '$.StoredFileName',
            RelativePath nvarchar(500) '$.RelativePath',
            ContentType nvarchar(100) '$.ContentType',
            FileSizeBytes bigint '$.FileSizeBytes'
        )
        WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> '';
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_AddAttachments
    @CashAdvanceRequestId int,
    @AttachmentsJson nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE CashAdvanceRequestId = @CashAdvanceRequestId)
    BEGIN
        RAISERROR('Cash advance request was not found.', 16, 1);
        RETURN;
    END

    IF ISJSON(@AttachmentsJson) = 1
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceAttachments
            (CashAdvanceRequestId, FileName, OriginalFileName, StoredFileName, RelativePath, ContentType, FileSizeBytes)
        SELECT @CashAdvanceRequestId,
               OriginalFileName,
               OriginalFileName,
               StoredFileName,
               RelativePath,
               ContentType,
               FileSizeBytes
        FROM OPENJSON(@AttachmentsJson)
        WITH
        (
            OriginalFileName nvarchar(260) '$.OriginalFileName',
            StoredFileName nvarchar(260) '$.StoredFileName',
            RelativePath nvarchar(500) '$.RelativePath',
            ContentType nvarchar(100) '$.ContentType',
            FileSizeBytes bigint '$.FileSizeBytes'
        )
        WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> '';
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_Create
    @RequestType nvarchar(50),
    @RequestorUserId int,
    @CustodianUserId int,
    @Amount decimal(19,4),
    @Purpose nvarchar(500),
    @ReceiptDetailsJson nvarchar(max) = NULL,
    @TransportationDetailsJson nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RequestTypeNormalized nvarchar(50) = LOWER(LTRIM(RTRIM(@RequestType)));
    DECLARE @Department nvarchar(100);
    DECLARE @CustodianRole nvarchar(50);
    DECLARE @CustodianDepartment nvarchar(100);
    DECLARE @CustodianFundAmount decimal(19,4);
    DECLARE @AvailableAmount decimal(19,4);
    DECLARE @UsedAmount decimal(19,4);
    DECLARE @ReplenishmentAmount decimal(19,4);
    DECLARE @ReceiptTotal decimal(19,4);
    DECLARE @TransportationTotal decimal(19,4);
    DECLARE @RequestTotal decimal(19,4);
    DECLARE @RequestNumber nvarchar(50);

    CREATE TABLE #ReceiptRows
    (
        OrNumber nvarchar(100) NULL,
        Company nvarchar(200) NULL,
        Tin nvarchar(100) NULL,
        Address nvarchar(500) NULL,
        NatureOfExpense nvarchar(300) NULL,
        CostCenter nvarchar(100) NULL,
        TaxType nvarchar(20) NULL,
        Amount decimal(19,4) NULL,
        OrDate date NULL
    );

    CREATE TABLE #TransportationRows
    (
        [Description] nvarchar(300) NULL,
        FromLocation nvarchar(200) NULL,
        ToLocation nvarchar(200) NULL,
        TransactionDate date NULL,
        Amount decimal(19,4) NULL
    );

    IF @RequestTypeNormalized NOT IN (N'petty_cash', N'petty_cash_advance')
    BEGIN
        RAISERROR('Request type must be Petty Cash or Petty Cash Advance.', 16, 1);
        RETURN;
    END

    IF @Amount <= 0 OR @Amount > 5000
    BEGIN
        RAISERROR('Petty cash amount must be greater than zero and must not exceed PHP 5,000.', 16, 1);
        RETURN;
    END

    IF @RequestTypeNormalized = N'petty_cash'
    BEGIN
        IF ISJSON(@ReceiptDetailsJson) <> 1
        BEGIN
            RAISERROR('Receipt details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #ReceiptRows
            (OrNumber, Company, Tin, Address, NatureOfExpense, CostCenter, TaxType, Amount, OrDate)
        SELECT LTRIM(RTRIM(COALESCE(OrNumberCamel, OrNumberPascal))),
               LTRIM(RTRIM(COALESCE(CompanyCamel, CompanyPascal))),
               LTRIM(RTRIM(COALESCE(TinCamel, TinPascal))),
               LTRIM(RTRIM(COALESCE(AddressCamel, AddressPascal))),
               LTRIM(RTRIM(COALESCE(NatureOfExpenseCodeCamel, NatureOfExpenseCodePascal, NatureOfExpenseCamel, NatureOfExpensePascal))),
               LTRIM(RTRIM(COALESCE(CostCenterCodeCamel, CostCenterCodePascal, CostCenterCamel, CostCenterPascal))),
               LTRIM(RTRIM(COALESCE(TaxTypeCamel, TaxTypePascal))),
               COALESCE(AmountCamel, AmountPascal),
               COALESCE(OrDateCamel, OrDatePascal)
        FROM OPENJSON(@ReceiptDetailsJson)
        WITH
        (
            OrNumberCamel nvarchar(100) '$.orNumber',
            OrNumberPascal nvarchar(100) '$.OrNumber',
            CompanyCamel nvarchar(200) '$.company',
            CompanyPascal nvarchar(200) '$.Company',
            TinCamel nvarchar(100) '$.tin',
            TinPascal nvarchar(100) '$.Tin',
            AddressCamel nvarchar(500) '$.address',
            AddressPascal nvarchar(500) '$.Address',
            NatureOfExpenseCodeCamel nvarchar(300) '$.natureOfExpenseCode',
            NatureOfExpenseCodePascal nvarchar(300) '$.NatureOfExpenseCode',
            NatureOfExpenseCamel nvarchar(300) '$.natureOfExpense',
            NatureOfExpensePascal nvarchar(300) '$.NatureOfExpense',
            CostCenterCodeCamel nvarchar(100) '$.costCenterCode',
            CostCenterCodePascal nvarchar(100) '$.CostCenterCode',
            CostCenterCamel nvarchar(100) '$.costCenter',
            CostCenterPascal nvarchar(100) '$.CostCenter',
            TaxTypeCamel nvarchar(20) '$.taxType',
            TaxTypePascal nvarchar(20) '$.TaxType',
            AmountCamel decimal(19,4) '$.amount',
            AmountPascal decimal(19,4) '$.Amount',
            OrDateCamel date '$.orDate',
            OrDatePascal date '$.OrDate'
        );

        IF ISJSON(@TransportationDetailsJson) <> 1
        BEGIN
            RAISERROR('Transportation details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #TransportationRows
            ([Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT LTRIM(RTRIM(COALESCE(DescriptionCamel, DescriptionPascal))),
               LTRIM(RTRIM(COALESCE(FromCamel, FromPascal))),
               LTRIM(RTRIM(COALESCE(ToCamel, ToPascal))),
               COALESCE(TransactionDateCamel, TransactionDatePascal),
               COALESCE(AmountCamel, AmountPascal)
        FROM OPENJSON(@TransportationDetailsJson)
        WITH
        (
            DescriptionCamel nvarchar(300) '$.description',
            DescriptionPascal nvarchar(300) '$.Description',
            FromCamel nvarchar(200) '$.from',
            FromPascal nvarchar(200) '$.From',
            ToCamel nvarchar(200) '$.to',
            ToPascal nvarchar(200) '$.To',
            TransactionDateCamel date '$.transactionDate',
            TransactionDatePascal date '$.TransactionDate',
            AmountCamel decimal(19,4) '$.amount',
            AmountPascal decimal(19,4) '$.Amount'
        );

        IF NOT EXISTS (SELECT 1 FROM #ReceiptRows)
           AND NOT EXISTS (SELECT 1 FROM #TransportationRows)
        BEGIN
            RAISERROR('At least one receipt or transportation row is required for petty cash reimbursement.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #ReceiptRows
            WHERE NULLIF(OrNumber, N'') IS NULL
               OR NULLIF(Company, N'') IS NULL
               OR NULLIF(Tin, N'') IS NULL
               OR NULLIF(Address, N'') IS NULL
               OR NULLIF(NatureOfExpense, N'') IS NULL
               OR NULLIF(CostCenter, N'') IS NULL
               OR Amount IS NULL
               OR Amount <= 0
               OR OrDate IS NULL
        )
        BEGIN
            RAISERROR('Complete every receipt row before submitting petty cash reimbursement.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #TransportationRows
            WHERE NULLIF([Description], N'') IS NULL
               OR NULLIF(FromLocation, N'') IS NULL
               OR NULLIF(ToLocation, N'') IS NULL
               OR TransactionDate IS NULL
               OR Amount IS NULL
               OR Amount <= 0
        )
        BEGIN
            RAISERROR('Complete every transportation row before submitting petty cash reimbursement.', 16, 1);
            RETURN;
        END

        SELECT @ReceiptTotal = COALESCE(SUM(Amount), 0)
        FROM #ReceiptRows;

        SELECT @TransportationTotal = COALESCE(SUM(Amount), 0)
        FROM #TransportationRows;

        SET @RequestTotal = COALESCE(@ReceiptTotal, 0) + COALESCE(@TransportationTotal, 0);

        IF @RequestTotal + 0.01 < @Amount
        BEGIN
            RAISERROR('Petty cash actual spent must be equal to or greater than the reimbursement amount.', 16, 1);
            RETURN;
        END

        IF @RequestTotal - @Amount > 5000
        BEGIN
            RAISERROR('The reimbursement excess must not exceed the petty cash request cap.', 16, 1);
            RETURN;
        END
    END

    SELECT @Department = Department
    FROM dbo.FMS_AppUsers
    WHERE UserId = @RequestorUserId
      AND Role = 'requestor'
      AND IsActive = 1;

    SELECT @CustodianRole = Role,
           @CustodianDepartment = Department,
           @CustodianFundAmount = COALESCE(PettyCashFundAmount, 20000)
    FROM dbo.FMS_AppUsers
    WHERE UserId = @CustodianUserId
      AND IsActive = 1;

    IF @Department IS NULL OR @CustodianRole <> N'custodian'
    BEGIN
        RAISERROR('A valid requestor and custodian are required.', 16, 1);
        RETURN;
    END

    IF LOWER(LTRIM(RTRIM(@CustodianDepartment))) <> LOWER(LTRIM(RTRIM(@Department)))
    BEGIN
        RAISERROR('Petty cash requests must use the custodian assigned to the requestor department.', 16, 1);
        RETURN;
    END

    SELECT @UsedAmount = COALESCE(SUM(
        CASE
            WHEN StatusId = 11 THEN 0
            WHEN RequestType = N'petty_cash' AND StatusId <> 8 THEN 0
            WHEN StatusId = 8 THEN COALESCE(AmountSpent, Amount - COALESCE(ReturnAmount, 0), Amount)
            ELSE Amount
        END
    ), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType IN (N'petty_cash', N'petty_cash_advance');

    SELECT @ReplenishmentAmount = COALESCE(SUM(Amount), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType = N'petty_cash_replenishment'
      AND StatusId = 15;

    SET @AvailableAmount = @CustodianFundAmount - (@UsedAmount - @ReplenishmentAmount);

    IF @Amount > @AvailableAmount
    BEGIN
        RAISERROR('Petty cash amount exceeds the custodian available fund.', 16, 1);
        RETURN;
    END

    SET @RequestNumber = CONCAT(N'PC-', YEAR(GETDATE()), N'-', RIGHT(CONCAT(N'000', (
        SELECT COUNT(1) + 1
        FROM dbo.FMS_CashAdvanceRequests
        WHERE RequestType IN (N'petty_cash', N'petty_cash_advance')
          AND YEAR(AuditDate) = YEAR(GETDATE())
    )), 3));

    WHILE EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE RequestNumber = @RequestNumber)
    BEGIN
        SET @RequestNumber = CONCAT(@RequestNumber, N'-', ABS(CHECKSUM(NEWID())) % 1000);
    END

    INSERT INTO dbo.FMS_CashAdvanceRequests
        (RequestNumber, RequestType, RequestorUserId, CurrentOwnerUserId, CustodianUserId, Department, Amount, RemainingAmount, Purpose, StatusId, DueDate)
    VALUES
        (@RequestNumber, @RequestTypeNormalized, @RequestorUserId, @RequestorUserId, @CustodianUserId, @Department, @Amount, @Amount, @Purpose, 1, DATEADD(DAY, 7, CONVERT(date, GETDATE())));

    DECLARE @CashAdvanceRequestId int = CONVERT(int, SCOPE_IDENTITY());

    IF @RequestTypeNormalized = N'petty_cash'
    BEGIN
        INSERT INTO dbo.FMS_PettyCashReceiptDetails
            (CashAdvanceRequestId, OrNumber, Company, Tin, Address, NatureOfExpense, CostCenter, TaxType, Amount, OrDate)
        SELECT @CashAdvanceRequestId,
               OrNumber,
               Company,
               Tin,
               Address,
               NatureOfExpense,
               CostCenter,
               TaxType,
               Amount,
               OrDate
        FROM #ReceiptRows;

        INSERT INTO dbo.FMS_PettyCashTransportationDetails
            (CashAdvanceRequestId, [Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT @CashAdvanceRequestId,
               [Description],
               FromLocation,
               ToLocation,
               TransactionDate,
               Amount
        FROM #TransportationRows;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'petty_cash_requested', @RequestorUserId, @Amount, 'Petty cash request submitted for department approval.');

    SELECT @CashAdvanceRequestId AS CashAdvanceRequestId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_CustodianDecision
    @CashAdvanceRequestId int,
    @CustodianUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestType nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @Amount decimal(19,4);
    DECLARE @AmountSpent decimal(19,4);
    DECLARE @Department nvarchar(100);
    DECLARE @Purpose nvarchar(500);
    DECLARE @RequestNumber nvarchar(50);

    SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @RequestorUserId = RequestorUserId,
           @Amount = Amount,
           @AmountSpent = AmountSpent,
           @Department = Department,
           @Purpose = Purpose,
           @RequestNumber = RequestNumber
    FROM dbo.FMS_CashAdvanceRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND CustodianUserId = @CustodianUserId
      AND RequestType IN (N'petty_cash', N'petty_cash_advance')
      AND EXISTS
      (
          SELECT 1
          FROM dbo.vw_FMS_AppUsers custodian
          WHERE custodian.UserId = @CustodianUserId
            AND custodian.Role = N'custodian'
            AND custodian.IsActive = 1
      );

    IF @RequestType IS NULL
    BEGIN
        RAISERROR('Petty cash request was not found for this custodian.', 16, 1);
        RETURN;
    END

    IF @StatusId = 12
    BEGIN
        IF @Approved = 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 11,
                CurrentOwnerUserId = @RequestorUserId,
                RemainingAmount = 0,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'rejected',
                @CustodianUserId,
                @Amount,
                COALESCE(@Notes, 'Custodian rejected the petty cash request.')
            );

            RETURN;
        END

        IF @RequestType = N'petty_cash'
        BEGIN
            DECLARE @ActualSpentAmount decimal(19,4);
            DECLARE @ExcessAmount decimal(19,4);
            DECLARE @NewRequestNumber nvarchar(50);
            DECLARE @NewCashAdvanceRequestId int;

            SELECT @ActualSpentAmount =
                COALESCE((SELECT SUM(Amount) FROM dbo.FMS_PettyCashReceiptDetails WHERE CashAdvanceRequestId = @CashAdvanceRequestId), 0) +
                COALESCE((SELECT SUM(Amount) FROM dbo.FMS_PettyCashTransportationDetails WHERE CashAdvanceRequestId = @CashAdvanceRequestId), 0);

            SET @ExcessAmount = CASE WHEN @ActualSpentAmount > @Amount THEN @ActualSpentAmount - @Amount ELSE 0 END;

            IF @ExcessAmount > 5000
            BEGIN
                RAISERROR('The reimbursement excess must not exceed the petty cash request cap.', 16, 1);
                RETURN;
            END

            IF @ExcessAmount > 0
            BEGIN
                CREATE TABLE #PettyCashSplitRows
                (
                    DetailType nvarchar(20) NOT NULL,
                    PettyCashReceiptDetailId int NULL,
                    PettyCashTransportationDetailId int NULL,
                    OriginalAmount decimal(19,4) NOT NULL,
                    ExcessAmount decimal(19,4) NOT NULL
                );

                ;WITH OrderedDetails AS
                (
                    SELECT N'receipt' AS DetailType,
                           PettyCashReceiptDetailId,
                           CAST(NULL AS int) AS PettyCashTransportationDetailId,
                           Amount,
                           0 AS SortGroup,
                           PettyCashReceiptDetailId AS SortId
                    FROM dbo.FMS_PettyCashReceiptDetails
                    WHERE CashAdvanceRequestId = @CashAdvanceRequestId

                    UNION ALL

                    SELECT N'transportation' AS DetailType,
                           CAST(NULL AS int) AS PettyCashReceiptDetailId,
                           PettyCashTransportationDetailId,
                           Amount,
                           1 AS SortGroup,
                           PettyCashTransportationDetailId AS SortId
                    FROM dbo.FMS_PettyCashTransportationDetails
                    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
                ),
                RunningDetails AS
                (
                    SELECT DetailType,
                           PettyCashReceiptDetailId,
                           PettyCashTransportationDetailId,
                           Amount,
                           COALESCE(SUM(Amount) OVER (ORDER BY SortGroup, SortId ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS AmountBefore
                    FROM OrderedDetails
                )
                INSERT INTO #PettyCashSplitRows
                    (DetailType, PettyCashReceiptDetailId, PettyCashTransportationDetailId, OriginalAmount, ExcessAmount)
                SELECT running.DetailType,
                       running.PettyCashReceiptDetailId,
                       running.PettyCashTransportationDetailId,
                       allocated.OriginalAmount,
                       running.Amount - allocated.OriginalAmount
                FROM RunningDetails running
                CROSS APPLY
                (
                    SELECT CASE
                        WHEN running.AmountBefore >= @Amount THEN 0
                        WHEN running.AmountBefore + running.Amount <= @Amount THEN running.Amount
                        ELSE @Amount - running.AmountBefore
                    END AS OriginalAmount
                ) allocated;

                SET @NewRequestNumber = CONCAT(N'PC-', YEAR(GETDATE()), N'-', RIGHT(CONCAT(N'000', (
                    SELECT COUNT(1) + 1
                    FROM dbo.FMS_CashAdvanceRequests
                    WHERE RequestType IN (N'petty_cash', N'petty_cash_advance')
                      AND YEAR(AuditDate) = YEAR(GETDATE())
                )), 3));

                WHILE EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE RequestNumber = @NewRequestNumber)
                BEGIN
                    SET @NewRequestNumber = CONCAT(@NewRequestNumber, N'-', ABS(CHECKSUM(NEWID())) % 1000);
                END

                INSERT INTO dbo.FMS_CashAdvanceRequests
                    (OriginalCashAdvanceRequestId, RequestNumber, RequestType, RequestorUserId, CurrentOwnerUserId, CustodianUserId, Department, Amount, RemainingAmount, Purpose, StatusId, DueDate)
                VALUES
                    (@CashAdvanceRequestId, @NewRequestNumber, N'petty_cash', @RequestorUserId, @RequestorUserId, @CustodianUserId, @Department, @ExcessAmount, @ExcessAmount, LEFT(CONCAT(N'Excess reimbursement for ', @RequestNumber, N': ', @Purpose), 500), 1, DATEADD(DAY, 7, CONVERT(date, GETDATE())));

                SET @NewCashAdvanceRequestId = CONVERT(int, SCOPE_IDENTITY());

                INSERT INTO dbo.FMS_PettyCashReceiptDetails
                    (CashAdvanceRequestId, OrNumber, Company, Tin, Address, NatureOfExpense, CostCenter, TaxType, Amount, OrDate)
                SELECT @NewCashAdvanceRequestId,
                       detail.OrNumber,
                       detail.Company,
                       detail.Tin,
                       detail.Address,
                       detail.NatureOfExpense,
                       detail.CostCenter,
                       detail.TaxType,
                       split.ExcessAmount,
                       detail.OrDate
                FROM dbo.FMS_PettyCashReceiptDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashReceiptDetailId = detail.PettyCashReceiptDetailId
                   AND split.DetailType = N'receipt'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.ExcessAmount > 0;

                INSERT INTO dbo.FMS_PettyCashTransportationDetails
                    (CashAdvanceRequestId, [Description], FromLocation, ToLocation, TransactionDate, Amount)
                SELECT @NewCashAdvanceRequestId,
                       detail.[Description],
                       detail.FromLocation,
                       detail.ToLocation,
                       detail.TransactionDate,
                       split.ExcessAmount
                FROM dbo.FMS_PettyCashTransportationDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashTransportationDetailId = detail.PettyCashTransportationDetailId
                   AND split.DetailType = N'transportation'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.ExcessAmount > 0;

                INSERT INTO dbo.FMS_CashAdvanceAttachments
                    (CashAdvanceRequestId, FileName, OriginalFileName, StoredFileName, RelativePath, ContentType, FileSizeBytes)
                SELECT @NewCashAdvanceRequestId,
                       FileName,
                       OriginalFileName,
                       StoredFileName,
                       RelativePath,
                       ContentType,
                       FileSizeBytes
                FROM dbo.FMS_CashAdvanceAttachments
                WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

                UPDATE detail
                SET Amount = split.OriginalAmount
                FROM dbo.FMS_PettyCashReceiptDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashReceiptDetailId = detail.PettyCashReceiptDetailId
                   AND split.DetailType = N'receipt'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.OriginalAmount > 0;

                DELETE detail
                FROM dbo.FMS_PettyCashReceiptDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashReceiptDetailId = detail.PettyCashReceiptDetailId
                   AND split.DetailType = N'receipt'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.OriginalAmount <= 0;

                UPDATE detail
                SET Amount = split.OriginalAmount
                FROM dbo.FMS_PettyCashTransportationDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashTransportationDetailId = detail.PettyCashTransportationDetailId
                   AND split.DetailType = N'transportation'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.OriginalAmount > 0;

                DELETE detail
                FROM dbo.FMS_PettyCashTransportationDetails detail
                INNER JOIN #PettyCashSplitRows split
                    ON split.PettyCashTransportationDetailId = detail.PettyCashTransportationDetailId
                   AND split.DetailType = N'transportation'
                WHERE detail.CashAdvanceRequestId = @CashAdvanceRequestId
                  AND split.OriginalAmount <= 0;

                INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
                VALUES (@NewCashAdvanceRequestId, 'petty_cash_requested', @RequestorUserId, @ExcessAmount, CONCAT(N'Excess petty cash reimbursement created from ', @RequestNumber, N'.'));
            END

            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 8,
                CurrentOwnerUserId = @RequestorUserId,
                RemainingAmount = 0,
                AmountSpent = Amount,
                LiquidationBaseAmount = Amount,
                ReturnAmount = 0,
                ExcessAmount = NULLIF(@ExcessAmount, 0),
                LiquidatedAt = GETDATE(),
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'approved_by_custodian',
                @CustodianUserId,
                @Amount,
                COALESCE(@Notes, 'Custodian approved the petty cash reimbursement.')
            );

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'fully_liquidated',
                @CustodianUserId,
                @Amount,
                'Petty cash reimbursement closed by custodian.'
            );

            IF @NewCashAdvanceRequestId IS NOT NULL
            BEGIN
                INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
                VALUES (@CashAdvanceRequestId, 'excess_created', @CustodianUserId, @ExcessAmount, CONCAT(N'Created ', @NewRequestNumber, N' for the excess petty cash reimbursement.'));
            END

            RETURN;
        END

        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 0,
            CurrentOwnerUserId = @RequestorUserId,
            RemainingAmount = Amount,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'petty_cash_released',
            @CustodianUserId,
            @Amount,
            COALESCE(@Notes, 'Custodian approved and released petty cash advance.')
        );

        RETURN;
    END

    IF @StatusId = 13
    BEGIN
        IF @Approved = 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 0,
                RemainingAmount = COALESCE(NULLIF(LiquidationBaseAmount, 0), Amount),
                ReturnAmount = NULL,
                ExcessAmount = NULL,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES (@CashAdvanceRequestId, 'returned', @CustodianUserId, @AmountSpent, COALESCE(@Notes, 'Custodian returned the petty cash liquidation for correction.'));

            RETURN;
        END

        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 8,
            RemainingAmount = 0,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'approved_by_custodian', @CustodianUserId, @AmountSpent, COALESCE(@Notes, 'Custodian approved the petty cash liquidation.'));

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'fully_liquidated', @CustodianUserId, @AmountSpent, 'Petty cash liquidation closed by custodian.');

        RETURN;
    END

    RAISERROR('Petty cash request is not waiting for custodian action.', 16, 1);
    RETURN;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_CreateReplenishment
    @CustodianUserId int,
    @Amount decimal(19,4),
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Department nvarchar(100);
    DECLARE @UsedAmount decimal(19,4);
    DECLARE @ReplenishmentAmount decimal(19,4);
    DECLARE @NeededAmount decimal(19,4);
    DECLARE @RequestNumber nvarchar(50);

    SELECT @Department = Department
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @CustodianUserId
      AND Role = N'custodian'
      AND IsActive = 1;

    IF @Department IS NULL
    BEGIN
        RAISERROR('A valid custodian is required.', 16, 1);
        RETURN;
    END

    IF @Amount <= 0
    BEGIN
        RAISERROR('Replenishment amount must be greater than zero.', 16, 1);
        RETURN;
    END

    SELECT @UsedAmount = COALESCE(SUM(
        CASE
            WHEN StatusId = 11 THEN 0
            WHEN RequestType = N'petty_cash' AND StatusId <> 8 THEN 0
            WHEN StatusId = 8 THEN COALESCE(AmountSpent, Amount - COALESCE(ReturnAmount, 0), Amount)
            ELSE Amount
        END
    ), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType IN (N'petty_cash', N'petty_cash_advance');

    SELECT @ReplenishmentAmount = COALESCE(SUM(Amount), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType = N'petty_cash_replenishment'
      AND StatusId IN (14, 15);

    SET @NeededAmount = @UsedAmount - @ReplenishmentAmount;

    IF @Amount > @NeededAmount
    BEGIN
        RAISERROR('Replenishment amount exceeds the fund amount currently needing replenishment.', 16, 1);
        RETURN;
    END

    SET @RequestNumber = CONCAT(N'PCR-', YEAR(GETDATE()), N'-', RIGHT(CONCAT(N'000', (
        SELECT COUNT(1) + 1
        FROM dbo.FMS_CashAdvanceRequests
        WHERE RequestType = N'petty_cash_replenishment'
          AND YEAR(AuditDate) = YEAR(GETDATE())
    )), 3));

    WHILE EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE RequestNumber = @RequestNumber)
    BEGIN
        SET @RequestNumber = CONCAT(@RequestNumber, N'-', ABS(CHECKSUM(NEWID())) % 1000);
    END

    INSERT INTO dbo.FMS_CashAdvanceRequests
        (RequestNumber, RfpRequestNumber, RequestType, RequestorUserId, CurrentOwnerUserId, CustodianUserId, Department, Amount, RemainingAmount, Purpose, StatusId, DueDate)
    VALUES
        (@RequestNumber, @RequestNumber, N'petty_cash_replenishment', @CustodianUserId, @CustodianUserId, @CustodianUserId, @Department, @Amount, 0, COALESCE(NULLIF(@Notes, N''), N'Petty cash fund replenishment'), 14, CONVERT(date, GETDATE()));

    DECLARE @CashAdvanceRequestId int = SCOPE_IDENTITY();

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'petty_cash_replenishment_created', @CustodianUserId, @Amount, COALESCE(@Notes, 'Custodian created a replenishment RFP request.'));

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'rfp_created', @CustodianUserId, @Amount, 'Replenishment RFP request created.');
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_SubmitReplenishmentCv
    @CashAdvanceRequestId int,
    @CustodianUserId int,
    @CvNumber nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestType nvarchar(50);
    DECLARE @Amount decimal(19,4);

    SET @CvNumber = NULLIF(LTRIM(RTRIM(@CvNumber)), N'');

    IF @CvNumber IS NULL
    BEGIN
        RAISERROR('CV Number is required.', 16, 1);
        RETURN;
    END

    SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @Amount = Amount
    FROM dbo.FMS_CashAdvanceRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND CustodianUserId = @CustodianUserId
      AND RequestType = N'petty_cash_replenishment'
      AND EXISTS
      (
          SELECT 1
          FROM dbo.vw_FMS_AppUsers custodian
          WHERE custodian.UserId = @CustodianUserId
            AND custodian.Role = N'custodian'
            AND custodian.IsActive = 1
      );

    IF @RequestType IS NULL
    BEGIN
        RAISERROR('Pending replenishment request was not found for this custodian.', 16, 1);
        RETURN;
    END

    IF @StatusId <> 14
    BEGIN
        RAISERROR('Replenishment request is not waiting for CV Number.', 16, 1);
        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = 15,
        CvNumber = @CvNumber,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'petty_cash_replenished',
        @CustodianUserId,
        @Amount,
        CONCAT('CV Number ', @CvNumber, ' submitted. Petty cash fund replenished.')
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_DepartmentDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL,
    @RfpDecision nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestType nvarchar(50);
    DECLARE @CustodianUserId int;
    DECLARE @UsesPettyCashWorkflow bit = 0;
    DECLARE @AmountSpent decimal(19,4);
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @ReturnAmount decimal(19,4);
    DECLARE @ExcessAmount decimal(19,4);
    DECLARE @RequestNumber nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @CurrentOwnerUserId int;
    DECLARE @Department nvarchar(100);
    DECLARE @Purpose nvarchar(500);
    DECLARE @RfpRequestNumber nvarchar(50);
    DECLARE @RfpDecisionNormalized nvarchar(20);

    SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @CustodianUserId = CustodianUserId,
           @AmountSpent = AmountSpent,
           @LiquidationBaseAmount = COALESCE(LiquidationBaseAmount, Amount),
           @RequestNumber = RequestNumber,
           @RequestorUserId = RequestorUserId,
           @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @Department = Department,
           @Purpose = Purpose,
           @ExcessAmount = ExcessAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @StatusId IS NULL
    BEGIN
        RETURN;
    END

    SET @UsesPettyCashWorkflow = CASE
        WHEN @RequestType IN (N'petty_cash', N'petty_cash_advance') AND @CustodianUserId IS NOT NULL THEN 1
        ELSE 0
    END;

    IF @UsesPettyCashWorkflow = 1 AND @StatusId = 1 AND @AmountSpent IS NULL
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = CASE WHEN @Approved = 1 THEN 12 ELSE 11 END,
            RemainingAmount = CASE WHEN @Approved = 1 THEN Amount ELSE 0 END,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            CASE WHEN @Approved = 1 THEN 'approved_by_department_head' ELSE 'rejected' END,
            @ApproverUserId,
            @LiquidationBaseAmount,
            COALESCE(@Notes, CASE WHEN @Approved = 1 THEN 'Department approved the petty cash request. Routed to custodian.' ELSE 'Department rejected the petty cash request.' END)
        );

        RETURN;
    END

    IF @StatusId = 5
    BEGIN
        IF @Approved = 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 0,
                RemainingAmount = COALESCE(NULLIF(LiquidationBaseAmount, 0), Amount),
                ReturnAmount = NULL,
                ExcessAmount = NULL,
                RfpDecision = NULL,
                RfpWaiveReason = NULL,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'returned',
                @ApproverUserId,
                @ExcessAmount,
                COALESCE(@Notes, 'Department returned the request for correction.')
            );

            RETURN;
        END

        IF ISNULL(@ExcessAmount, 0) <= 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 8,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            RETURN;
        END

        SET @RfpDecisionNormalized = LOWER(LTRIM(RTRIM(COALESCE(@RfpDecision, N'create'))));

        IF @RfpDecisionNormalized NOT IN (N'create', N'waive')
        BEGIN
            RAISERROR('RFP decision must be Create RFP or Waive RFP.', 16, 1);
            RETURN;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            RAISERROR('Waive RFP reason is required.', 16, 1);
            RETURN;
        END

        IF @RfpDecisionNormalized = N'create'
        BEGIN
            SET @RfpRequestNumber = CONCAT(@RequestNumber, '-RFP-', @CashAdvanceRequestId);

            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 6,
                RfpRequestNumber = @RfpRequestNumber,
                RfpDecision = 'create',
                RfpWaiveReason = NULL,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'rfp_created',
                @ApproverUserId,
                @ExcessAmount,
                COALESCE(@Notes, 'Department approved RFP creation. Requestor must upload the RFP attachment.')
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 8,
                RfpDecision = 'waive',
                RfpWaiveReason = @Notes,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'rfp_waived',
                @ApproverUserId,
                @ExcessAmount,
                @Notes
            );
        END

        RETURN;
    END

    IF @StatusId <> 1
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 0,
            RemainingAmount = COALESCE(NULLIF(LiquidationBaseAmount, 0), Amount),
            ReturnAmount = NULL,
            ExcessAmount = NULL,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'returned',
            @ApproverUserId,
            @AmountSpent,
            COALESCE(@Notes, 'Department returned the request for correction.')
        );

        RETURN;
    END

    SET @ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END;
    SET @ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END;

    IF @UsesPettyCashWorkflow = 1
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 13,
            ReturnAmount = NULLIF(@ReturnAmount, 0),
            ExcessAmount = 0,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'approved_by_department_head',
            @ApproverUserId,
            @AmountSpent,
            COALESCE(@Notes, 'Department approved the petty cash liquidation. Routed to custodian.')
        );

        RETURN;
    END

    IF ISNULL(@ExcessAmount, 0) > 0
    BEGIN
        SET @RfpDecisionNormalized = LOWER(LTRIM(RTRIM(COALESCE(@RfpDecision, N'create'))));

        IF @RfpDecisionNormalized NOT IN (N'create', N'waive')
        BEGIN
            RAISERROR('RFP decision must be Create RFP or Waive RFP.', 16, 1);
            RETURN;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            RAISERROR('Waive RFP reason is required.', 16, 1);
            RETURN;
        END

        IF @RfpDecisionNormalized = N'create'
        BEGIN
            SET @RfpRequestNumber = CONCAT(@RequestNumber, '-RFP-', @CashAdvanceRequestId);
        END

        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = CASE
                WHEN @RfpDecisionNormalized = N'create' THEN 6
                ELSE 4
            END,
            ReturnAmount = NULL,
            ExcessAmount = @ExcessAmount,
            RfpRequestNumber = CASE WHEN @RfpDecisionNormalized = N'create' THEN @RfpRequestNumber ELSE RfpRequestNumber END,
            RfpDecision = @RfpDecisionNormalized,
            RfpWaiveReason = CASE WHEN @RfpDecisionNormalized = N'waive' THEN @Notes ELSE NULL END,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'approved_by_department_head', @ApproverUserId, @AmountSpent, @Notes);

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            CASE WHEN @RfpDecisionNormalized = N'create' THEN 'rfp_created' ELSE 'rfp_waived' END,
            @ApproverUserId,
            @ExcessAmount,
            CASE
                WHEN @RfpDecisionNormalized = N'create' THEN COALESCE(@Notes, 'Department approved RFP creation. Requestor must upload the RFP attachment.')
                ELSE @Notes
            END
        );

        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = CASE
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 2
            ELSE 4
        END,
        ReturnAmount = NULLIF(@ReturnAmount, 0),
        ExcessAmount = NULLIF(@ExcessAmount, 0),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'approved_by_department_head', @ApproverUserId, @AmountSpent, @Notes);
END
GO
