IF DB_ID(N'FundManagementSystem') IS NULL
BEGIN
    CREATE DATABASE FundManagementSystem;
END
GO

USE FundManagementSystem;
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_AppUsers
    (
        UserId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppUsers PRIMARY KEY,
        Username nvarchar(50) NOT NULL,
        DisplayName nvarchar(200) NOT NULL,
        Department nvarchar(100) NOT NULL,
        Role nvarchar(50) NOT NULL,
        Title nvarchar(100) NOT NULL,
        PasswordHash varbinary(32) NOT NULL,
        PettyCashFundAmount decimal(19,4) NULL,
        IsActive bit NOT NULL CONSTRAINT DF_AppUsers_IsActive DEFAULT (1),
        AuditDate datetime NOT NULL CONSTRAINT DF_AppUsers_AuditDate DEFAULT (GETDATE()),
        UpdatedAt datetime NULL,
        CONSTRAINT CK_AppUsers_Role CHECK (Role IN ('admin', 'requestor', 'department_head', 'accounting', 'cashier', 'custodian'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_AppUsers_Username' AND object_id = OBJECT_ID(N'dbo.FMS_AppUsers'))
BEGIN
    CREATE UNIQUE INDEX UX_AppUsers_Username ON dbo.FMS_AppUsers(Username);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers)
BEGIN
    INSERT INTO dbo.FMS_AppUsers (Username, DisplayName, Department, Role, Title, PasswordHash)
    VALUES
        (N'admin', N'System Admin', N'Administration', N'admin', N'Administrator', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123'))),
        (N'requestor', N'Ruru Pogi', N'MIS', N'requestor', N'Requestor', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123'))),
        (N'depthead', N'Migs Llanera', N'MIS', N'department_head', N'Department Head', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123'))),
        (N'accounting', N'Joselle De Guzman', N'Accounting', N'accounting', N'Accounting Reviewer', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123'))),
        (N'cashier', N'Anna Vea', N'Accounting', N'cashier', N'Cashier', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123')));
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceStatuses', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceStatuses
    (
        StatusId int NOT NULL CONSTRAINT PK_CashAdvanceStatuses PRIMARY KEY,
        StatusCode nvarchar(50) NOT NULL,
        DisplayName nvarchar(100) NOT NULL,
        SortOrder int NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_CashAdvanceStatuses_IsActive DEFAULT (1),
        CONSTRAINT UX_CashAdvanceStatuses_StatusCode UNIQUE (StatusCode)
    );
END
GO

MERGE dbo.FMS_CashAdvanceStatuses AS target
USING
(
    VALUES
        (0, N'pending_liquidation', N'Pending Liquidation', 0),
        (1, N'pending_department_approval', N'Pending Department Approval', 1),
        (2, N'pending_cashier_return', N'Pending Cashier Return', 2),
        (3, N'pending_cashier_closure', N'Pending Cashier Closure', 3),
        (4, N'pending_accounting_review', N'Pending Accounting Review', 4),
        (5, N'pending_rfp_department_approval', N'Pending RFP Department Approval', 5),
        (6, N'pending_rfp_attachment', N'Pending RFP Attachment', 6),
        (7, N'partially_liquidated', N'Partially Liquidated', 7),
        (8, N'fully_liquidated', N'Fully Liquidated', 8),
        (9, N'transferred', N'Transferred', 9),
        (10, N'rfp_created', N'RFP Created', 10),
        (11, N'rejected', N'Rejected', 11),
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

IF OBJECT_ID(N'dbo.FMS_CashAdvanceRequests', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceRequests
    (
        CashAdvanceRequestId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceRequests PRIMARY KEY,
        OriginalCashAdvanceRequestId int NULL,
        RequestNumber nvarchar(50) NOT NULL,
        RequestorUserId int NOT NULL,
        CurrentOwnerUserId int NULL,
        Department nvarchar(100) NOT NULL,
        CompanyID int NULL,
        CompanyCode nvarchar(50) NULL,
        Amount decimal(19,4) NOT NULL,
        RemainingAmount decimal(19,4) NULL,
        LiquidationBaseAmount decimal(19,4) NULL,
        PendingTransferFromUserId int NULL,
        PendingTransferToUserId int NULL,
        PendingTransferAmount decimal(19,4) NULL,
        PendingTransferIsWholeRequest bit NULL,
        PendingTransferNotes nvarchar(1000) NULL,
        AmountSpent decimal(19,4) NULL,
        ReturnAmount decimal(19,4) NULL,
        ExcessAmount decimal(19,4) NULL,
        Purpose nvarchar(500) NOT NULL,
        StatusId int NOT NULL CONSTRAINT DF_CashAdvanceRequests_StatusId DEFAULT (0),
        LiquidationNotes nvarchar(max) NULL,
        RfpRequestNumber nvarchar(50) NULL,
        CvNumber nvarchar(50) NULL,
        RfpDecision nvarchar(20) NULL,
        RfpWaiveReason nvarchar(1000) NULL,
        DueDate date NULL,
        LiquidatedAt datetime NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_CashAdvanceRequests_AuditDate DEFAULT (GETDATE()),
        UpdatedAt datetime NULL,
        CONSTRAINT FK_CashAdvanceRequests_AppUsers FOREIGN KEY (RequestorUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT FK_CashAdvanceRequests_CurrentOwner FOREIGN KEY (CurrentOwnerUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT FK_CashAdvanceRequests_PendingTransferFrom FOREIGN KEY (PendingTransferFromUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT FK_CashAdvanceRequests_PendingTransferTo FOREIGN KEY (PendingTransferToUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT FK_CashAdvanceRequests_Original FOREIGN KEY (OriginalCashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT FK_CashAdvanceRequests_Statuses FOREIGN KEY (StatusId) REFERENCES dbo.FMS_CashAdvanceStatuses(StatusId),
        CONSTRAINT CK_CashAdvanceRequests_Amount CHECK (Amount >= 0),
        CONSTRAINT CK_CashAdvanceRequests_RemainingAmount CHECK (RemainingAmount IS NULL OR RemainingAmount >= 0),
        CONSTRAINT CK_CashAdvanceRequests_PendingTransferAmount CHECK (PendingTransferAmount IS NULL OR PendingTransferAmount > 0),
        CONSTRAINT CK_CashAdvanceRequests_AmountSpent CHECK (AmountSpent IS NULL OR AmountSpent >= 0),
        CONSTRAINT CK_CashAdvanceRequests_ReturnAmount CHECK (ReturnAmount IS NULL OR ReturnAmount >= 0),
        CONSTRAINT CK_CashAdvanceRequests_ExcessAmount CHECK (ExcessAmount IS NULL OR ExcessAmount >= 0)
    );
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'StatusId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD StatusId int NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'Status') IS NOT NULL
BEGIN
    UPDATE r
    SET StatusId = s.StatusId
    FROM dbo.FMS_CashAdvanceRequests r
    INNER JOIN dbo.FMS_CashAdvanceStatuses s ON s.StatusCode = r.Status
    WHERE r.StatusId IS NULL;
END
GO

UPDATE dbo.FMS_CashAdvanceRequests
SET StatusId = 0
WHERE StatusId IS NULL;
GO

ALTER TABLE dbo.FMS_CashAdvanceRequests ALTER COLUMN StatusId int NOT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_Status')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT CK_CashAdvanceRequests_Status;
END
GO

DECLARE @CashAdvanceRequestsStatusDefault sysname;

SELECT @CashAdvanceRequestsStatusDefault = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests')
  AND c.name = N'Status';

IF @CashAdvanceRequestsStatusDefault IS NOT NULL
BEGIN
    EXEC(N'ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT ' + QUOTENAME(@CashAdvanceRequestsStatusDefault));
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CashAdvanceRequests_RequestNumber' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    CREATE UNIQUE INDEX UX_CashAdvanceRequests_RequestNumber ON dbo.FMS_CashAdvanceRequests(RequestNumber);
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_StatusDepartment' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    DROP INDEX IX_CashAdvanceRequests_StatusDepartment ON dbo.FMS_CashAdvanceRequests;
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_PendingTransferTo' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    DROP INDEX IX_CashAdvanceRequests_PendingTransferTo ON dbo.FMS_CashAdvanceRequests;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'Status') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP COLUMN Status;
END
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests')
      AND c.name = N'StatusId'
)
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT DF_CashAdvanceRequests_StatusId DEFAULT (0) FOR StatusId;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_Statuses')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_Statuses FOREIGN KEY (StatusId) REFERENCES dbo.FMS_CashAdvanceStatuses(StatusId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_StatusDepartment' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    CREATE INDEX IX_CashAdvanceRequests_StatusDepartment ON dbo.FMS_CashAdvanceRequests(StatusId, Department);
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CurrentOwnerUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CurrentOwnerUserId int NULL;
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

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RemainingAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RemainingAmount decimal(19,4) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'LiquidationBaseAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD LiquidationBaseAmount decimal(19,4) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RfpDecision') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RfpDecision nvarchar(20) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CvNumber') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CvNumber nvarchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RfpWaiveReason') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RfpWaiveReason nvarchar(1000) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_CurrentOwner')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_CurrentOwner FOREIGN KEY (CurrentOwnerUserId) REFERENCES dbo.FMS_AppUsers(UserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_RemainingAmount')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT CK_CashAdvanceRequests_RemainingAmount CHECK (RemainingAmount IS NULL OR RemainingAmount >= 0);
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'PendingTransferFromUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD PendingTransferFromUserId int NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'PendingTransferToUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD PendingTransferToUserId int NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'PendingTransferAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD PendingTransferAmount decimal(19,4) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'PendingTransferIsWholeRequest') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD PendingTransferIsWholeRequest bit NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'PendingTransferNotes') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD PendingTransferNotes nvarchar(1000) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_PendingTransferFrom')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_PendingTransferFrom FOREIGN KEY (PendingTransferFromUserId) REFERENCES dbo.FMS_AppUsers(UserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_PendingTransferTo')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_PendingTransferTo FOREIGN KEY (PendingTransferToUserId) REFERENCES dbo.FMS_AppUsers(UserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_PendingTransferAmount')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT CK_CashAdvanceRequests_PendingTransferAmount CHECK (PendingTransferAmount IS NULL OR PendingTransferAmount > 0);
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceAttachments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceAttachments
    (
        AttachmentId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceAttachments PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        FileName nvarchar(260) NOT NULL,
        UploadedAt datetime NOT NULL CONSTRAINT DF_CashAdvanceAttachments_UploadedAt DEFAULT (GETDATE()),
        CONSTRAINT FK_CashAdvanceAttachments_Requests FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId)
    );
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceRequests_Dtl', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceRequests_Dtl
    (
        CashAdvanceRequestDtlId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceRequests_Dtl PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        Vendor nvarchar(200) NULL,
        VendorCode varchar(50) NULL,
        [Description] nvarchar(500) NOT NULL,
        Project nvarchar(200) NULL,
        ProjectCode nvarchar(20) NULL,
        ProfitCenter nvarchar(200) NULL,
        ProfitCenterCode nvarchar(8) NULL,
        Amount decimal(19,4) NOT NULL,
        InvoiceRef nvarchar(100) NOT NULL,
        ExpenseType nvarchar(200) NULL,
        ExpenseTypeCode varchar(50) NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_CashAdvanceRequests_Dtl_AuditDate DEFAULT (GETDATE()),
        CONSTRAINT FK_CashAdvanceRequests_Dtl_Requests FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT CK_CashAdvanceRequests_Dtl_Amount CHECK (Amount > 0)
    );
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'VendorCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD VendorCode varchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'Vendor') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN Vendor nvarchar(200) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProjectCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ProjectCode nvarchar(20) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'Project') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN Project nvarchar(200) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProfitCenterCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ProfitCenterCode nvarchar(8) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProfitCenter') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN ProfitCenter nvarchar(200) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ExpenseTypeCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ExpenseTypeCode varchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ExpenseType') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN ExpenseType nvarchar(200) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_Dtl_Request' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests_Dtl'))
BEGIN
    CREATE INDEX IX_CashAdvanceRequests_Dtl_Request ON dbo.FMS_CashAdvanceRequests_Dtl(CashAdvanceRequestId, CashAdvanceRequestDtlId);
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts
    (
        ReceiptId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceAcknowledgementReceipts PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        ReceiptNumber nvarchar(50) NOT NULL,
        ReturnAmount decimal(19,4) NOT NULL,
        AttachmentFileName nvarchar(260) NULL,
        AttachmentStoredFileName nvarchar(260) NULL,
        AttachmentRelativePath nvarchar(500) NULL,
        AttachmentContentType nvarchar(100) NULL,
        AttachmentFileSizeBytes bigint NULL,
        DepositSlipFileName nvarchar(260) NULL,
        DepositSlipStoredFileName nvarchar(260) NULL,
        DepositSlipRelativePath nvarchar(500) NULL,
        DepositSlipContentType nvarchar(100) NULL,
        DepositSlipFileSizeBytes bigint NULL,
        DepositDate datetime NULL,
        DepositAmount decimal(19,4) NULL,
        DepositoryBank nvarchar(150) NULL,
        CreatedByUserId int NOT NULL,
        Notes nvarchar(1000) NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_CashAdvanceAcknowledgementReceipts_AuditDate DEFAULT (GETDATE()),
        CONSTRAINT FK_CashAdvanceAcknowledgementReceipts_Requests FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT FK_CashAdvanceAcknowledgementReceipts_AppUsers FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT CK_CashAdvanceAcknowledgementReceipts_ReturnAmount CHECK (ReturnAmount >= 0),
        CONSTRAINT CK_CashAdvanceAcknowledgementReceipts_DepositAmount CHECK (DepositAmount IS NULL OR DepositAmount >= 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CashAdvanceAcknowledgementReceipts_ReceiptNumber' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceAcknowledgementReceipts'))
BEGIN
    CREATE UNIQUE INDEX UX_CashAdvanceAcknowledgementReceipts_ReceiptNumber ON dbo.FMS_CashAdvanceAcknowledgementReceipts(ReceiptNumber);
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceHistory
    (
        HistoryId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceHistory PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        Action nvarchar(50) NOT NULL,
        ActorUserId int NULL,
        Amount decimal(19,4) NULL,
        Notes nvarchar(max) NULL,
        AuditDate datetime NOT NULL CONSTRAINT DF_CashAdvanceHistory_AuditDate DEFAULT (GETDATE()),
        CONSTRAINT FK_CashAdvanceHistory_Requests FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT FK_CashAdvanceHistory_AppUsers FOREIGN KEY (ActorUserId) REFERENCES dbo.FMS_AppUsers(UserId)
    );
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'LiquidationNotes') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ALTER COLUMN LiquidationNotes nvarchar(max) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceHistory', N'Notes') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceHistory ALTER COLUMN Notes nvarchar(max) NULL;
END
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceTransfers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_CashAdvanceTransfers
    (
        TransferId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CashAdvanceTransfers PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL,
        CreatedCashAdvanceRequestId int NULL,
        FromUserId int NOT NULL,
        ToUserId int NOT NULL,
        TransferAmount decimal(19,4) NOT NULL,
        IsWholeRequest bit NOT NULL,
        Status nvarchar(30) NOT NULL CONSTRAINT DF_CashAdvanceTransfers_Status DEFAULT ('pending'),
        Notes nvarchar(1000) NULL,
        ResponseNotes nvarchar(1000) NULL,
        RequestedAt datetime NOT NULL CONSTRAINT DF_CashAdvanceTransfers_RequestedAt DEFAULT (GETDATE()),
        RespondedAt datetime NULL,
        CONSTRAINT FK_CashAdvanceTransfers_Requests FOREIGN KEY (CashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT FK_CashAdvanceTransfers_CreatedRequests FOREIGN KEY (CreatedCashAdvanceRequestId) REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        CONSTRAINT FK_CashAdvanceTransfers_FromUsers FOREIGN KEY (FromUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT FK_CashAdvanceTransfers_ToUsers FOREIGN KEY (ToUserId) REFERENCES dbo.FMS_AppUsers(UserId),
        CONSTRAINT CK_CashAdvanceTransfers_Amount CHECK (TransferAmount > 0),
        CONSTRAINT CK_CashAdvanceTransfers_Status CHECK (Status IN ('pending', 'acknowledged', 'denied'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_PendingTransferTo' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    CREATE INDEX IX_CashAdvanceRequests_PendingTransferTo ON dbo.FMS_CashAdvanceRequests(PendingTransferToUserId, StatusId)
    WHERE PendingTransferToUserId IS NOT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceTransfers_RequestStatus' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceTransfers'))
BEGIN
    CREATE INDEX IX_CashAdvanceTransfers_RequestStatus ON dbo.FMS_CashAdvanceTransfers(CashAdvanceRequestId, Status);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceTransfers_ToUserStatus' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceTransfers'))
BEGIN
    CREATE INDEX IX_CashAdvanceTransfers_ToUserStatus ON dbo.FMS_CashAdvanceTransfers(ToUserId, Status, RequestedAt);
END
GO

INSERT INTO dbo.FMS_CashAdvanceTransfers
    (CashAdvanceRequestId, FromUserId, ToUserId, TransferAmount, IsWholeRequest, Status, Notes, RequestedAt)
SELECT r.CashAdvanceRequestId,
       r.PendingTransferFromUserId,
       r.PendingTransferToUserId,
       r.PendingTransferAmount,
       COALESCE(r.PendingTransferIsWholeRequest, 0),
       'pending',
       r.PendingTransferNotes,
       COALESCE(r.UpdatedAt, r.AuditDate)
FROM dbo.FMS_CashAdvanceRequests r
WHERE r.PendingTransferFromUserId IS NOT NULL
  AND r.PendingTransferToUserId IS NOT NULL
  AND r.PendingTransferAmount IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.FMS_CashAdvanceTransfers t
      WHERE t.CashAdvanceRequestId = r.CashAdvanceRequestId
        AND t.ToUserId = r.PendingTransferToUserId
        AND t.Status = 'pending'
  );
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'OriginalFileName') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAttachments ADD OriginalFileName nvarchar(260) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'StoredFileName') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAttachments ADD StoredFileName nvarchar(260) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'RelativePath') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAttachments ADD RelativePath nvarchar(500) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'ContentType') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAttachments ADD ContentType nvarchar(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'FileSizeBytes') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAttachments ADD FileSizeBytes bigint NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'AttachmentStoredFileName') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD AttachmentStoredFileName nvarchar(260) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'AttachmentRelativePath') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD AttachmentRelativePath nvarchar(500) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'AttachmentContentType') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD AttachmentContentType nvarchar(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'AttachmentFileSizeBytes') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD AttachmentFileSizeBytes bigint NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositSlipFileName') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositSlipFileName nvarchar(260) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositSlipStoredFileName') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositSlipStoredFileName nvarchar(260) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositSlipRelativePath') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositSlipRelativePath nvarchar(500) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositSlipContentType') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositSlipContentType nvarchar(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositSlipFileSizeBytes') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositSlipFileSizeBytes bigint NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositDate') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositDate datetime NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositAmount decimal(19,4) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAcknowledgementReceipts', N'DepositoryBank') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD DepositoryBank nvarchar(150) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceAcknowledgementReceipts_DepositAmount' AND parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceAcknowledgementReceipts'))
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceAcknowledgementReceipts ADD CONSTRAINT CK_CashAdvanceAcknowledgementReceipts_DepositAmount CHECK (DepositAmount IS NULL OR DepositAmount >= 0);
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests)
BEGIN
    INSERT INTO dbo.FMS_CashAdvanceRequests (RequestNumber, RequestorUserId, CurrentOwnerUserId, Department, Amount, RemainingAmount, Purpose, StatusId, DueDate)
    SELECT N'CA-2026-001', UserId, UserId, Department, 5000, 5000, N'Business travel for client meeting', 0, '2026-06-25'
    FROM dbo.FMS_AppUsers
    WHERE Username = N'requestor';
END
GO

UPDATE dbo.FMS_CashAdvanceRequests
SET CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
    RemainingAmount = COALESCE(
        RemainingAmount,
        CASE
            WHEN StatusId IN (0, 7) THEN Amount
            ELSE 0
        END
    )
WHERE CurrentOwnerUserId IS NULL
   OR RemainingAmount IS NULL;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_GetAll
    @IncludeInactive bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive, PettyCashFundAmount
    FROM dbo.FMS_AppUsers
    WHERE @IncludeInactive = 1 OR IsActive = 1
    ORDER BY Role, DisplayName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Auth_Login
    @Username nvarchar(50),
    @Password nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PasswordHash varbinary(32) = HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password));

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive, PettyCashFundAmount
    FROM dbo.FMS_AppUsers
    WHERE Username = @Username
      AND PasswordHash = @PasswordHash
      AND IsActive = 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_OtherBusinessPartners_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT LTRIM(RTRIM(BP_Code)) AS BP_Code,
           LTRIM(RTRIM(BP_Name)) AS BP_Name
    FROM dbo.FMS_OtherBP_CLI
    WHERE NULLIF(LTRIM(RTRIM(BP_Code)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(BP_Name)), N'') IS NOT NULL
    ORDER BY LTRIM(RTRIM(BP_Name));
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Companies_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ObjectId int = OBJECT_ID(N'dbo.vw_FMS_Company', N'V');
    DECLARE @IdColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @ObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @IdColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'ID', N'Id', N'CompanyId', N'CompanyID', N'CompanyCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'ID' THEN 1
            WHEN N'Id' THEN 2
            WHEN N'CompanyId' THEN 3
            WHEN N'CompanyID' THEN 4
            WHEN N'CompanyCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END;

        SELECT TOP (1) @NameColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Name', N'CompanyName')
        ORDER BY CASE [name]
            WHEN N'Name' THEN 1
            WHEN N'CompanyName' THEN 2
            ELSE 3
        END;
    END;

    IF @NameColumn IS NULL
    BEGIN
        SELECT CAST(NULL AS int) AS CompanyId,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH Companies AS
    (
        SELECT ' + CASE
                WHEN @IdColumn IS NULL THEN N'CAST(NULL AS int)'
                ELSE N'TRY_CONVERT(int, ' + QUOTENAME(@IdColumn) + N')'
            END + N' AS CompanyId,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS [Name]
        FROM dbo.vw_FMS_Company
    )
    SELECT CompanyId,
           [Name]
    FROM Companies
    WHERE CompanyId IS NOT NULL
      AND [Name] IS NOT NULL
    GROUP BY CompanyId, [Name]
    ORDER BY CompanyId, [Name];';

    EXEC sys.sp_executesql @Sql;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CompanyReferences_GetByCompany
    @CompanyId int,
    @ReferenceKind nvarchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CompanyObjectId int = OBJECT_ID(N'dbo.vw_FMS_Company', N'V');
    DECLARE @IdColumn sysname = NULL;
    DECLARE @SourceColumn sysname = CASE @ReferenceKind
        WHEN N'vendor' THEN N'VendorPayee_Table'
        WHEN N'project' THEN N'Projects_Table'
        WHEN N'profit-center' THEN N'ProfitCenter_Table'
        ELSE NULL
    END;
    DECLARE @SourceTable nvarchar(512) = NULL;
    DECLARE @SourceObject sysname = NULL;
    DECLARE @ReferenceObjectId int = NULL;
    DECLARE @CodeColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @CompanyObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @IdColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @CompanyObjectId
          AND [name] IN (N'ID', N'Id', N'CompanyId', N'CompanyID', N'CompanyCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'ID' THEN 1
            WHEN N'Id' THEN 2
            WHEN N'CompanyId' THEN 3
            WHEN N'CompanyID' THEN 4
            WHEN N'CompanyCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END;
    END;

    IF @CompanyObjectId IS NULL
       OR @IdColumn IS NULL
       OR @SourceColumn IS NULL
       OR NOT EXISTS
       (
           SELECT 1
           FROM sys.columns
           WHERE [object_id] = @CompanyObjectId
             AND [name] = @SourceColumn
       )
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @LookupSql nvarchar(max) = N'
    SELECT TOP (1) @SourceTable = NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(512), ' + QUOTENAME(@SourceColumn) + N') COLLATE DATABASE_DEFAULT)), N'''')
    FROM dbo.vw_FMS_Company
    WHERE TRY_CONVERT(int, ' + QUOTENAME(@IdColumn) + N') = @CompanyId;';

    EXEC sys.sp_executesql
        @LookupSql,
        N'@CompanyId int, @SourceTable nvarchar(512) OUTPUT',
        @CompanyId,
        @SourceTable OUTPUT;

    SET @SourceTable = NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(@SourceTable, N'[', N''), N']', N''))), N'');
    SET @SourceObject = PARSENAME(@SourceTable, 1);

    IF @SourceObject IS NULL AND LEN(@SourceTable) <= 128
    BEGIN
        SET @SourceObject = @SourceTable;
    END;

    IF @SourceObject IS NULL
       OR @SourceObject COLLATE Latin1_General_BIN2 LIKE N'%[^A-Za-z0-9_]%'
       OR OBJECT_ID(N'FineReport..' + QUOTENAME(@SourceObject)) IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    SET @ReferenceObjectId = OBJECT_ID(N'FineReport..' + QUOTENAME(@SourceObject));

    SELECT TOP (1) @CodeColumn = [name]
    FROM FineReport.sys.columns
    WHERE [object_id] = @ReferenceObjectId
      AND
      (
          (@ReferenceKind = N'vendor'
           AND [name] IN (N'BP_Code', N'BPCode', N'VendorPayee_Code', N'VendorPayeeCode', N'VendorCode', N'CardCode', N'Code'))
          OR (@ReferenceKind = N'project'
              AND [name] IN (N'ProjCode', N'ProjectCode', N'Code'))
          OR (@ReferenceKind = N'profit-center'
              AND [name] IN (N'OcrCode', N'PrcCode', N'ProfitCenterCode', N'CostCenterCode', N'CenterCode', N'Code'))
      )
    ORDER BY CASE
        WHEN @ReferenceKind = N'vendor' THEN CASE [name]
            WHEN N'BP_Code' THEN 1
            WHEN N'BPCode' THEN 2
            WHEN N'VendorPayee_Code' THEN 3
            WHEN N'VendorPayeeCode' THEN 4
            WHEN N'VendorCode' THEN 5
            WHEN N'CardCode' THEN 6
            WHEN N'Code' THEN 7
            ELSE 8
        END
        WHEN @ReferenceKind = N'project' THEN CASE [name]
            WHEN N'ProjCode' THEN 1
            WHEN N'ProjectCode' THEN 2
            WHEN N'Code' THEN 3
            ELSE 4
        END
        WHEN @ReferenceKind = N'profit-center' THEN CASE [name]
            WHEN N'OcrCode' THEN 1
            WHEN N'PrcCode' THEN 2
            WHEN N'ProfitCenterCode' THEN 3
            WHEN N'CostCenterCode' THEN 4
            WHEN N'CenterCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END
    END;

    SELECT TOP (1) @NameColumn = [name]
    FROM FineReport.sys.columns
    WHERE [object_id] = @ReferenceObjectId
      AND
      (
          (@ReferenceKind = N'vendor'
           AND [name] IN (N'BP_Name', N'BPName', N'VendorPayee_Name', N'VendorPayeeName', N'VendorName', N'CardName', N'Name'))
          OR (@ReferenceKind = N'project'
              AND [name] IN (N'ProjName', N'ProjectName', N'Name', N'Description'))
          OR (@ReferenceKind = N'profit-center'
              AND [name] IN (N'OcrName', N'PrcName', N'ProfitCenterName', N'CostCenterName', N'CenterName', N'Name', N'Description'))
      )
    ORDER BY CASE
        WHEN @ReferenceKind = N'vendor' THEN CASE [name]
            WHEN N'BP_Name' THEN 1
            WHEN N'BPName' THEN 2
            WHEN N'VendorPayee_Name' THEN 3
            WHEN N'VendorPayeeName' THEN 4
            WHEN N'VendorName' THEN 5
            WHEN N'CardName' THEN 6
            WHEN N'Name' THEN 7
            ELSE 8
        END
        WHEN @ReferenceKind = N'project' THEN CASE [name]
            WHEN N'ProjName' THEN 1
            WHEN N'ProjectName' THEN 2
            WHEN N'Name' THEN 3
            WHEN N'Description' THEN 4
            ELSE 5
        END
        WHEN @ReferenceKind = N'profit-center' THEN CASE [name]
            WHEN N'OcrName' THEN 1
            WHEN N'PrcName' THEN 2
            WHEN N'ProfitCenterName' THEN 3
            WHEN N'CostCenterName' THEN 4
            WHEN N'CenterName' THEN 5
            WHEN N'Name' THEN 6
            WHEN N'Description' THEN 7
            ELSE 8
        END
    END;

    IF @CodeColumn IS NULL AND @NameColumn IS NOT NULL
    BEGIN
        SET @CodeColumn = @NameColumn;
    END;

    IF @ReferenceKind = N'profit-center'
       AND @SourceObject COLLATE Latin1_General_CI_AS = N'vwProfitCenters'
       AND EXISTS
       (
           SELECT 1
           FROM FineReport.sys.columns
           WHERE [object_id] = @ReferenceObjectId
             AND [name] = N'OcrCode'
       )
    BEGIN
        SET @CodeColumn = N'OcrCode';
    END;

    IF @NameColumn IS NULL AND @CodeColumn IS NOT NULL
    BEGIN
        SET @NameColumn = @CodeColumn;
    END;

    IF @CodeColumn IS NULL OR @NameColumn IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @CodeFilter nvarchar(max) = N'';

    IF @ReferenceKind = N'profit-center'
       AND @SourceObject COLLATE Latin1_General_CI_AS = N'vwProfitCenters'
    BEGIN
        SET @CodeFilter = N'
      AND Code LIKE N''OD-DP%''';
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH ReferenceRows AS
    (
        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), ' + QUOTENAME(@CodeColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Code,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS [Name]
        FROM FineReport..' + QUOTENAME(@SourceObject) + N'
    )
    SELECT Code,
           MIN([Name]) AS [Name]
    FROM ReferenceRows
    WHERE Code IS NOT NULL
      AND [Name] IS NOT NULL' + @CodeFilter + N'
    GROUP BY Code
    ORDER BY MIN([Name]);';

    EXEC sys.sp_executesql @Sql;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_BusinessPartners_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'vendor';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Projects_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'project';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProfitCenters_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'profit-center';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CostCenters_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'profit-center';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Projects_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    WITH Projects AS
    (
        SELECT NULLIF(LTRIM(RTRIM(ProjCode COLLATE DATABASE_DEFAULT)), N'') AS ProjCode,
               NULLIF(LTRIM(RTRIM(ProjName COLLATE DATABASE_DEFAULT)), N'') AS ProjName
        FROM FineReport..vwProjects
    )
    SELECT ProjCode,
           MIN(ProjName) AS ProjName
    FROM Projects
    WHERE ProjCode IS NOT NULL
      AND ProjName IS NOT NULL
    GROUP BY ProjCode
    ORDER BY MIN(ProjName);
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProfitCenters_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    WITH ProfitCenters AS
    (
        SELECT NULLIF(LTRIM(RTRIM(OcrCode COLLATE DATABASE_DEFAULT)), N'') AS OcrCode,
               NULLIF(LTRIM(RTRIM(OcrName COLLATE DATABASE_DEFAULT)), N'') AS OcrName
        FROM FineReport..vwProfitCenters
        WHERE OcrCode COLLATE DATABASE_DEFAULT LIKE N'OD-DP%'
    )
    SELECT OcrCode,
           MIN(OcrName) AS OcrName
    FROM ProfitCenters
    WHERE OcrCode IS NOT NULL
      AND OcrName IS NOT NULL
    GROUP BY OcrCode
    ORDER BY OcrCode;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_ExpenseTypes_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ObjectId int = OBJECT_ID(N'dbo.vw_FMS_ExpenseType', N'V');
    DECLARE @CodeColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @ObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @CodeColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Expense_Code', N'ExpenseCode', N'ExpenseTypeCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'Expense_Code' THEN 1
            WHEN N'ExpenseCode' THEN 2
            WHEN N'ExpenseTypeCode' THEN 3
            WHEN N'Code' THEN 4
            ELSE 5
        END;

        SELECT TOP (1) @NameColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Expense_Name', N'ExpenseName', N'ExpenseType', N'Name', N'Description')
        ORDER BY CASE [name]
            WHEN N'Expense_Name' THEN 1
            WHEN N'ExpenseName' THEN 2
            WHEN N'ExpenseType' THEN 3
            WHEN N'Name' THEN 4
            WHEN N'Description' THEN 5
            ELSE 6
        END;
    END;

    IF @CodeColumn IS NULL OR @NameColumn IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(50)) AS Expense_Code,
               CAST(N'' AS nvarchar(200)) AS Expense_Name
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH ExpenseTypes AS
    (
        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), ' + QUOTENAME(@CodeColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Expense_Code,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Expense_Name
        FROM dbo.vw_FMS_ExpenseType
    )
    SELECT Expense_Code,
           MIN(Expense_Name) AS Expense_Name
    FROM ExpenseTypes
    WHERE Expense_Code IS NOT NULL
      AND Expense_Name IS NOT NULL
    GROUP BY Expense_Code
    ORDER BY MIN(Expense_Name);';

    EXEC sys.sp_executesql @Sql;
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
                      (@Role = 'department_head' AND processedHistory.Action IN ('approved_by_department_head', 'rfp_created', 'rfp_waived', 'returned'))
                      OR (@Role = 'accounting' AND processedHistory.Action IN ('approved_by_accounting', 'returned'))
                      OR (@Role = 'cashier' AND processedHistory.Action IN ('acknowledged', 'fully_liquidated'))
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
                (@Role = 'requestor' AND COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId)
                OR (@Role = 'department_head' AND COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId)
                OR (@Role = 'department_head' AND r.Department = @Department AND r.StatusId IN (0, 1, 5, 7))
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

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_GetAccountingReport
    @UserId int,
    @FromDate datetime = NULL,
    @ToDate datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RequestNumber,
           COALESCE(NULLIF(LTRIM(RTRIM(d.VendorCode)), ''), N'') AS VendorCode,
           COALESCE(d.[Description], N'') AS [Description],
           COALESCE(NULLIF(LTRIM(RTRIM(d.ProjectCode)), N''), N'') AS ProjectCode,
           COALESCE(d.ProfitCenterCode, N'') AS ProfitCenterCode,
           d.Amount,
           COALESCE(d.InvoiceRef, N'') AS InvoiceRef,
           COALESCE(NULLIF(LTRIM(RTRIM(d.ExpenseTypeCode)), ''), N'') AS ExpenseTypeCode
    FROM dbo.FMS_CashAdvanceRequests_Dtl d
    INNER JOIN dbo.FMS_CashAdvanceRequests r ON r.CashAdvanceRequestId = d.CashAdvanceRequestId
    WHERE EXISTS
    (
        SELECT 1
        FROM dbo.FMS_CashAdvanceHistory accountingHistory
        WHERE accountingHistory.CashAdvanceRequestId = d.CashAdvanceRequestId
          AND accountingHistory.ActorUserId = @UserId
          AND accountingHistory.Action IN ('approved_by_accounting', 'returned')
          AND (@FromDate IS NULL OR accountingHistory.AuditDate >= @FromDate)
          AND (@ToDate IS NULL OR accountingHistory.AuditDate < DATEADD(DAY, 1, CONVERT(date, @ToDate)))
    )
    ORDER BY r.RequestNumber, d.CashAdvanceRequestDtlId;
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
    DECLARE @LiquidatingUserRole nvarchar(50);
    DECLARE @LiquidatingUserDepartment nvarchar(100);
    DECLARE @ShouldClaimFullCustody bit = 0;
    DECLARE @ReceiptDetailTotal decimal(19,4) = 0;

    CREATE TABLE #ReceiptRows
    (
        VendorCode varchar(50) NULL,
        [Description] nvarchar(500) NULL,
        ProjectCode nvarchar(20) NULL,
        ProfitCenterCode nvarchar(8) NULL,
        Amount decimal(19,4) NULL,
        InvoiceRef nvarchar(100) NULL,
        ExpenseTypeCode varchar(50) NULL
    );

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @LiquidationBaseAmount = COALESCE(RemainingAmount, Amount),
           @RequestDepartment = Department
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    SELECT @LiquidatingUserRole = Role,
           @LiquidatingUserDepartment = Department
    FROM dbo.FMS_AppUsers
    WHERE UserId = @LiquidatingUserId
      AND IsActive = 1;

    SET @ActorUserId = COALESCE(@LiquidatingUserId, @CurrentOwnerUserId);

    IF @LiquidatingUserId IS NOT NULL AND @LiquidatingUserId <> @CurrentOwnerUserId
    BEGIN
        IF @LiquidatingUserRole = N'department_head'
           AND LOWER(LTRIM(RTRIM(COALESCE(@LiquidatingUserDepartment, N'')))) = LOWER(LTRIM(RTRIM(COALESCE(@RequestDepartment, N''))))
        BEGIN
            SET @ShouldClaimFullCustody = 1;
        END
        ELSE
        BEGIN
            THROW 51000, 'Only the current owner or department approver can submit liquidation.', 1;
        END
    END

    IF ISJSON(COALESCE(@ReceiptDetailsJson, N'[]')) <> 1
    BEGIN
        THROW 51000, 'Receipt details are invalid.', 1;
    END

    INSERT INTO #ReceiptRows
        (VendorCode, [Description], ProjectCode, ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode)
    SELECT LTRIM(RTRIM(COALESCE(VendorCodeCamel, VendorCodePascal))),
           LTRIM(RTRIM(COALESCE(DescriptionCamel, DescriptionPascal))),
           LTRIM(RTRIM(COALESCE(ProjectCodeCamel, ProjectCodePascal))),
           LTRIM(RTRIM(COALESCE(ProfitCenterCodeCamel, ProfitCenterCodePascal))),
           COALESCE(AmountCamel, AmountPascal),
           LTRIM(RTRIM(COALESCE(InvoiceRefCamel, InvoiceRefPascal))),
           LTRIM(RTRIM(COALESCE(ExpenseTypeCodeCamel, ExpenseTypeCodePascal)))
    FROM OPENJSON(COALESCE(@ReceiptDetailsJson, N'[]'))
    WITH
    (
        VendorCodeCamel varchar(50) '$.vendorCode',
        VendorCodePascal varchar(50) '$.VendorCode',
        DescriptionCamel nvarchar(500) '$.description',
        DescriptionPascal nvarchar(500) '$.Description',
        ProjectCodeCamel nvarchar(20) '$.projectCode',
        ProjectCodePascal nvarchar(20) '$.ProjectCode',
        ProfitCenterCodeCamel nvarchar(8) '$.profitCenterCode',
        ProfitCenterCodePascal nvarchar(8) '$.ProfitCenterCode',
        AmountCamel decimal(19,4) '$.amount',
        AmountPascal decimal(19,4) '$.Amount',
        InvoiceRefCamel nvarchar(100) '$.invoiceRef',
        InvoiceRefPascal nvarchar(100) '$.InvoiceRef',
        ExpenseTypeCodeCamel varchar(50) '$.expenseTypeCode',
        ExpenseTypeCodePascal varchar(50) '$.ExpenseTypeCode'
    );

    IF NOT EXISTS (SELECT 1 FROM #ReceiptRows)
    BEGIN
        THROW 51000, 'At least one receipt detail row is required for liquidation.', 1;
    END

    IF EXISTS
    (
        SELECT 1
        FROM #ReceiptRows
        WHERE NULLIF(VendorCode, '') IS NULL
           OR NULLIF([Description], N'') IS NULL
           OR NULLIF(ProjectCode, N'') IS NULL
           OR NULLIF(ProfitCenterCode, N'') IS NULL
           OR Amount IS NULL
           OR Amount <= 0
           OR NULLIF(InvoiceRef, N'') IS NULL
           OR NULLIF(ExpenseTypeCode, '') IS NULL
    )
    BEGIN
        THROW 51000, 'Complete every receipt detail row before submitting liquidation.', 1;
    END

    SELECT @ReceiptDetailTotal = COALESCE(SUM(Amount), 0)
    FROM #ReceiptRows;

    IF ABS(@ReceiptDetailTotal - @AmountSpent) > 0.01
    BEGIN
        THROW 51000, 'Liquidation amount must match the receipt detail total.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET AmountSpent = @AmountSpent,
        CurrentOwnerUserId = CASE WHEN @ShouldClaimFullCustody = 1 THEN @LiquidatingUserId ELSE CurrentOwnerUserId END,
        RemainingAmount = 0,
        LiquidationBaseAmount = @LiquidationBaseAmount,
        ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END,
        ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END,
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
        THROW 51000, 'Cash advance request is not ready for liquidation or has a pending transfer acknowledgement.', 1;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'liquidation_submitted', @ActorUserId, @AmountSpent, @Notes);

    DELETE FROM dbo.FMS_CashAdvanceRequests_Dtl
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceRequests_Dtl
        (CashAdvanceRequestId, VendorCode, [Description], ProjectCode, ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode)
    SELECT @CashAdvanceRequestId,
           VendorCode,
           [Description],
           ProjectCode,
           ProfitCenterCode,
           Amount,
           InvoiceRef,
           ExpenseTypeCode
    FROM #ReceiptRows;
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_SubmitRfpAttachment
    @CashAdvanceRequestId int,
    @Notes nvarchar(max) = NULL,
    @AttachmentsJson nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentOwnerUserId int;
    DECLARE @ExcessAmount decimal(19,4);

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @ExcessAmount = ExcessAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId = 6
      AND RfpDecision = 'create';

    IF @CurrentOwnerUserId IS NULL
    BEGIN
        THROW 51013, 'Cash advance request is not waiting for an RFP attachment.', 1;
    END

    IF ISJSON(@AttachmentsJson) <> 1
       OR NOT EXISTS
       (
           SELECT 1
           FROM OPENJSON(@AttachmentsJson)
           WITH (OriginalFileName nvarchar(260) '$.OriginalFileName')
           WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> ''
       )
    BEGIN
        THROW 51014, 'RFP attachment is required.', 1;
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

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = 4,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'rfp_attachment_uploaded',
        @CurrentOwnerUserId,
        @ExcessAmount,
        COALESCE(@Notes, 'Requestor uploaded the RFP attachment for accounting review.')
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_Transfer
    @CashAdvanceRequestId int,
    @ToUserId int,
    @Amount decimal(19,4) = 0,
    @TransferWholeRequest bit = 0,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestNumber nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @CurrentOwnerUserId int;
    DECLARE @CurrentOwnerName nvarchar(200);
    DECLARE @CurrentOwnerDepartment nvarchar(100);
    DECLARE @ToUserName nvarchar(200);
    DECLARE @ToDepartment nvarchar(100);
    DECLARE @ExistingPendingTransferToUserId int;
    DECLARE @AvailableAmount decimal(19,4);
    DECLARE @TransferAmount decimal(19,4);
    DECLARE @TransferIsWholeRequest bit;

    SELECT @ToUserName = DisplayName,
           @ToDepartment = Department
    FROM dbo.FMS_AppUsers
    WHERE UserId = @ToUserId
      AND IsActive = 1
      AND Role IN ('requestor', 'department_head');

    IF @ToUserName IS NULL
    BEGIN
        THROW 51002, 'Transfer target must be an active requestor or department approver.', 1;
    END

    BEGIN TRANSACTION;

    SELECT @StatusId = r.StatusId,
           @RequestNumber = r.RequestNumber,
           @RequestorUserId = r.RequestorUserId,
           @CurrentOwnerUserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId),
           @CurrentOwnerName = owner.DisplayName,
           @CurrentOwnerDepartment = owner.Department,
           @ExistingPendingTransferToUserId = r.PendingTransferToUserId,
           @AvailableAmount = COALESCE(r.RemainingAmount, r.Amount)
    FROM dbo.FMS_CashAdvanceRequests r WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FMS_AppUsers owner ON owner.UserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId)
    WHERE r.CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @StatusId IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51003, 'Cash advance request was not found.', 1;
    END

    IF LOWER(LTRIM(RTRIM(COALESCE(@ToDepartment, N'')))) <> LOWER(LTRIM(RTRIM(COALESCE(@CurrentOwnerDepartment, N''))))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51015, 'Transfer target must be in the same department as the current owner.', 1;
    END

    IF @StatusId NOT IN (0, 7)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51004, 'Only requests pending liquidation can be transferred.', 1;
    END

    IF @CurrentOwnerUserId = @ToUserId
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51006, 'Cash advance request is already assigned to the selected user.', 1;
    END

    IF @ExistingPendingTransferToUserId IS NOT NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51007, 'Cash advance request already has a pending transfer acknowledgement.', 1;
    END

    SET @TransferAmount = CASE WHEN @TransferWholeRequest = 1 THEN @AvailableAmount ELSE @Amount END;
    SET @TransferIsWholeRequest = CASE WHEN @TransferWholeRequest = 1 OR @TransferAmount = @AvailableAmount THEN 1 ELSE 0 END;

    IF @TransferAmount <= 0 OR @TransferAmount > @AvailableAmount
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51005, 'Transfer amount must be greater than zero and not exceed the remaining request amount.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET PendingTransferFromUserId = @CurrentOwnerUserId,
        PendingTransferToUserId = @ToUserId,
        PendingTransferAmount = @TransferAmount,
        PendingTransferIsWholeRequest = @TransferIsWholeRequest,
        PendingTransferNotes = @Notes,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceTransfers
        (CashAdvanceRequestId, FromUserId, ToUserId, TransferAmount, IsWholeRequest, Status, Notes)
    VALUES
        (@CashAdvanceRequestId, @CurrentOwnerUserId, @ToUserId, @TransferAmount, @TransferIsWholeRequest, 'pending', @Notes);

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'transfer_requested',
        @CurrentOwnerUserId,
        @TransferAmount,
        COALESCE(
            @Notes,
            CASE
                WHEN @TransferIsWholeRequest = 1 THEN CONCAT('Whole request transfer requested for ', @ToUserName, '.')
                ELSE CONCAT('Partial transfer requested for ', @ToUserName, '.')
            END
        )
    );

    COMMIT TRANSACTION;
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_TransferResponse
    @CashAdvanceRequestId int,
    @ReceiverUserId int,
    @Accepted bit,
    @Notes nvarchar(1000) = NULL,
    @TransferId int = NULL
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestNumber nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @CurrentOwnerUserId int;
    DECLARE @PendingTransferFromUserId int;
    DECLARE @PendingTransferToUserId int;
    DECLARE @PendingTransferAmount decimal(19,4);
    DECLARE @PendingTransferIsWholeRequest bit;
    DECLARE @ReceiverName nvarchar(200);
    DECLARE @ReceiverDepartment nvarchar(100);
    DECLARE @Purpose nvarchar(500);
    DECLARE @DueDate date;
    DECLARE @CompanyID int;
    DECLARE @CompanyCode nvarchar(50);
    DECLARE @AvailableAmount decimal(19,4);
    DECLARE @NewRequestNumber nvarchar(50);
    DECLARE @NewCashAdvanceRequestId int;

    BEGIN TRANSACTION;

    SELECT @StatusId = r.StatusId,
           @RequestNumber = r.RequestNumber,
           @RequestorUserId = r.RequestorUserId,
           @CurrentOwnerUserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId),
           @PendingTransferFromUserId = r.PendingTransferFromUserId,
           @PendingTransferToUserId = r.PendingTransferToUserId,
           @PendingTransferAmount = r.PendingTransferAmount,
           @PendingTransferIsWholeRequest = r.PendingTransferIsWholeRequest,
           @Purpose = r.Purpose,
           @DueDate = r.DueDate,
           @CompanyID = r.CompanyID,
           @CompanyCode = r.CompanyCode,
           @AvailableAmount = COALESCE(r.RemainingAmount, r.Amount),
           @ReceiverName = receiver.DisplayName,
           @ReceiverDepartment = receiver.Department
    FROM dbo.FMS_CashAdvanceRequests r WITH (UPDLOCK, HOLDLOCK)
    LEFT JOIN dbo.FMS_AppUsers receiver ON receiver.UserId = @ReceiverUserId AND receiver.IsActive = 1
    WHERE r.CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @TransferId IS NOT NULL AND NOT EXISTS
    (
        SELECT 1
        FROM dbo.FMS_CashAdvanceTransfers WITH (UPDLOCK, HOLDLOCK)
        WHERE TransferId = @TransferId
          AND CashAdvanceRequestId = @CashAdvanceRequestId
          AND ToUserId = @ReceiverUserId
          AND Status = 'pending'
    )
    BEGIN
        SET @TransferId = NULL;
    END

    IF @TransferId IS NULL
    BEGIN
        SELECT TOP (1) @TransferId = TransferId
        FROM dbo.FMS_CashAdvanceTransfers WITH (UPDLOCK, HOLDLOCK)
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId
          AND ToUserId = @ReceiverUserId
          AND Status = 'pending'
        ORDER BY RequestedAt DESC, TransferId DESC;
    END

    IF @StatusId IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51008, 'Cash advance request was not found.', 1;
    END

    IF @ReceiverName IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51009, 'Receiver user was not found.', 1;
    END

    IF @PendingTransferToUserId IS NULL OR @PendingTransferToUserId <> @ReceiverUserId
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51010, 'No pending transfer acknowledgement exists for this receiver.', 1;
    END

    IF @Accepted = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET PendingTransferFromUserId = NULL,
            PendingTransferToUserId = NULL,
            PendingTransferAmount = NULL,
            PendingTransferIsWholeRequest = NULL,
            PendingTransferNotes = NULL,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        IF @TransferId IS NOT NULL
        BEGIN
            UPDATE dbo.FMS_CashAdvanceTransfers
            SET Status = 'denied',
                ResponseNotes = @Notes,
                RespondedAt = GETDATE()
            WHERE TransferId = @TransferId;
        END

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'transfer_denied',
            @ReceiverUserId,
            @PendingTransferAmount,
            COALESCE(@Notes, CONCAT('Transfer denied by ', @ReceiverName, '.'))
        );

        COMMIT TRANSACTION;
        RETURN;
    END

    IF @StatusId NOT IN (0, 7)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51011, 'Only requests pending liquidation can be acknowledged for transfer.', 1;
    END

    IF @PendingTransferAmount IS NULL OR @PendingTransferAmount <= 0 OR @PendingTransferAmount > @AvailableAmount
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51012, 'Pending transfer amount is no longer valid.', 1;
    END

    IF @PendingTransferIsWholeRequest = 1 OR @PendingTransferAmount = @AvailableAmount
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET CurrentOwnerUserId = @ReceiverUserId,
            Department = @ReceiverDepartment,
            RemainingAmount = @AvailableAmount,
            PendingTransferFromUserId = NULL,
            PendingTransferToUserId = NULL,
            PendingTransferAmount = NULL,
            PendingTransferIsWholeRequest = NULL,
            PendingTransferNotes = NULL,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        IF @TransferId IS NOT NULL
        BEGIN
            UPDATE dbo.FMS_CashAdvanceTransfers
            SET Status = 'acknowledged',
                ResponseNotes = @Notes,
                RespondedAt = GETDATE()
            WHERE TransferId = @TransferId;
        END

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'transfer_acknowledged',
            @ReceiverUserId,
            @PendingTransferAmount,
            COALESCE(@Notes, CONCAT('Whole request transfer acknowledged by ', @ReceiverName, '.'))
        );

        COMMIT TRANSACTION;
        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET RemainingAmount = @AvailableAmount - @PendingTransferAmount,
        PendingTransferFromUserId = NULL,
        PendingTransferToUserId = NULL,
        PendingTransferAmount = NULL,
        PendingTransferIsWholeRequest = NULL,
        PendingTransferNotes = NULL,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    SET @NewRequestNumber = CONCAT(LEFT(@RequestNumber, 40), '-T-', RIGHT(REPLACE(CONVERT(nvarchar(36), NEWID()), '-', ''), 6));

    WHILE EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE RequestNumber = @NewRequestNumber)
    BEGIN
        SET @NewRequestNumber = CONCAT(LEFT(@RequestNumber, 40), '-T-', RIGHT(REPLACE(CONVERT(nvarchar(36), NEWID()), '-', ''), 6));
    END

    INSERT INTO dbo.FMS_CashAdvanceRequests
        (OriginalCashAdvanceRequestId, RequestNumber, RequestorUserId, CurrentOwnerUserId, Department, CompanyID, CompanyCode, Amount, RemainingAmount, Purpose, StatusId, DueDate)
    VALUES
        (@CashAdvanceRequestId, @NewRequestNumber, @RequestorUserId, @ReceiverUserId, @ReceiverDepartment, @CompanyID, @CompanyCode, @PendingTransferAmount, @PendingTransferAmount, @Purpose, 0, @DueDate);

    SET @NewCashAdvanceRequestId = CONVERT(int, SCOPE_IDENTITY());

    IF @TransferId IS NOT NULL
    BEGIN
        UPDATE dbo.FMS_CashAdvanceTransfers
        SET Status = 'acknowledged',
            CreatedCashAdvanceRequestId = @NewCashAdvanceRequestId,
            ResponseNotes = @Notes,
            RespondedAt = GETDATE()
        WHERE TransferId = @TransferId;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'transfer_acknowledged',
        @ReceiverUserId,
        @PendingTransferAmount,
        COALESCE(@Notes, CONCAT('Partial transfer acknowledged by ', @ReceiverName, '.'))
    );

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @NewCashAdvanceRequestId,
        'transfer_acknowledged',
        @ReceiverUserId,
        @PendingTransferAmount,
        COALESCE(@Notes, CONCAT('Partial transfer accepted from ', @RequestNumber, '.'))
    );

    COMMIT TRANSACTION;
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
            THROW 51015, 'RFP decision must be Create RFP or Waive RFP.', 1;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            THROW 51016, 'Waive RFP reason is required.', 1;
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

    IF ISNULL(@ExcessAmount, 0) > 0
    BEGIN
        SET @RfpDecisionNormalized = LOWER(LTRIM(RTRIM(COALESCE(@RfpDecision, N'create'))));

        IF @RfpDecisionNormalized NOT IN (N'create', N'waive')
        BEGIN
            THROW 51015, 'RFP decision must be Create RFP or Waive RFP.', 1;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            THROW 51016, 'Waive RFP reason is required.', 1;
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_CashierCreateReceipt
    @CashAdvanceRequestId int,
    @CashierUserId int,
    @ReceiptNumber nvarchar(50),
    @AttachmentFileName nvarchar(260) = NULL,
    @AttachmentStoredFileName nvarchar(260) = NULL,
    @AttachmentRelativePath nvarchar(500) = NULL,
    @AttachmentContentType nvarchar(100) = NULL,
    @AttachmentFileSizeBytes bigint = NULL,
    @DepositSlipFileName nvarchar(260) = NULL,
    @DepositSlipStoredFileName nvarchar(260) = NULL,
    @DepositSlipRelativePath nvarchar(500) = NULL,
    @DepositSlipContentType nvarchar(100) = NULL,
    @DepositSlipFileSizeBytes bigint = NULL,
    @DepositDate datetime = NULL,
    @DepositAmount decimal(19,4) = NULL,
    @DepositoryBank nvarchar(150) = NULL,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnAmount decimal(19,4);

    SELECT @ReturnAmount = ReturnAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId = 2;

    IF @ReturnAmount IS NULL
    BEGIN
        THROW 51001, 'Cash advance request is not ready for a cashier receipt.', 1;
    END

    IF EXISTS
    (
        SELECT 1
        FROM dbo.FMS_CashAdvanceAcknowledgementReceipts
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId
    )
    BEGIN
        UPDATE dbo.FMS_CashAdvanceAcknowledgementReceipts
        SET ReceiptNumber = @ReceiptNumber,
            ReturnAmount = @ReturnAmount,
            AttachmentFileName = CASE WHEN @AttachmentFileName IS NULL THEN AttachmentFileName ELSE @AttachmentFileName END,
            AttachmentStoredFileName = CASE WHEN @AttachmentStoredFileName IS NULL THEN AttachmentStoredFileName ELSE @AttachmentStoredFileName END,
            AttachmentRelativePath = CASE WHEN @AttachmentRelativePath IS NULL THEN AttachmentRelativePath ELSE @AttachmentRelativePath END,
            AttachmentContentType = CASE WHEN @AttachmentContentType IS NULL THEN AttachmentContentType ELSE @AttachmentContentType END,
            AttachmentFileSizeBytes = CASE WHEN @AttachmentFileSizeBytes IS NULL THEN AttachmentFileSizeBytes ELSE @AttachmentFileSizeBytes END,
            DepositSlipFileName = CASE WHEN @DepositSlipFileName IS NULL THEN DepositSlipFileName ELSE @DepositSlipFileName END,
            DepositSlipStoredFileName = CASE WHEN @DepositSlipStoredFileName IS NULL THEN DepositSlipStoredFileName ELSE @DepositSlipStoredFileName END,
            DepositSlipRelativePath = CASE WHEN @DepositSlipRelativePath IS NULL THEN DepositSlipRelativePath ELSE @DepositSlipRelativePath END,
            DepositSlipContentType = CASE WHEN @DepositSlipContentType IS NULL THEN DepositSlipContentType ELSE @DepositSlipContentType END,
            DepositSlipFileSizeBytes = CASE WHEN @DepositSlipFileSizeBytes IS NULL THEN DepositSlipFileSizeBytes ELSE @DepositSlipFileSizeBytes END,
            DepositDate = CASE WHEN @DepositDate IS NULL THEN DepositDate ELSE @DepositDate END,
            DepositAmount = CASE WHEN @DepositAmount IS NULL THEN DepositAmount ELSE @DepositAmount END,
            DepositoryBank = CASE WHEN @DepositoryBank IS NULL THEN DepositoryBank ELSE @DepositoryBank END,
            CreatedByUserId = @CashierUserId,
            Notes = @Notes,
            AuditDate = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceAcknowledgementReceipts
            (CashAdvanceRequestId, ReceiptNumber, ReturnAmount, AttachmentFileName, AttachmentStoredFileName, AttachmentRelativePath, AttachmentContentType, AttachmentFileSizeBytes, DepositSlipFileName, DepositSlipStoredFileName, DepositSlipRelativePath, DepositSlipContentType, DepositSlipFileSizeBytes, DepositDate, DepositAmount, DepositoryBank, CreatedByUserId, Notes)
        VALUES
            (@CashAdvanceRequestId, @ReceiptNumber, @ReturnAmount, @AttachmentFileName, @AttachmentStoredFileName, @AttachmentRelativePath, @AttachmentContentType, @AttachmentFileSizeBytes, @DepositSlipFileName, @DepositSlipStoredFileName, @DepositSlipRelativePath, @DepositSlipContentType, @DepositSlipFileSizeBytes, @DepositDate, @DepositAmount, @DepositoryBank, @CashierUserId, @Notes);
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = CASE
            WHEN @DepositSlipRelativePath IS NULL THEN 2
            ELSE 4
        END,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'acknowledged',
        @CashierUserId,
        @ReturnAmount,
        CASE
            WHEN @DepositSlipRelativePath IS NULL THEN COALESCE(@Notes, 'Cashier saved acknowledgement receipt as draft. Deposit Slip/AR attachment pending.')
            ELSE COALESCE(@Notes, 'Cashier uploaded Deposit Slip/AR attachment. Sent to accounting.')
        END
    );
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_AccountingDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExcessAmount decimal(19,4);
    DECLARE @ReturnAmount decimal(19,4);
    DECLARE @Amount decimal(19,4);
    DECLARE @AmountSpent decimal(19,4);
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @HasCashierReceipt bit;
    DECLARE @RfpDecision nvarchar(20);
    DECLARE @HasRfpAttachment bit;

    SELECT @ExcessAmount = ExcessAmount,
           @ReturnAmount = ReturnAmount,
           @Amount = Amount,
           @AmountSpent = AmountSpent,
           @LiquidationBaseAmount = COALESCE(LiquidationBaseAmount, Amount),
           @RfpDecision = RfpDecision,
           @HasRfpAttachment = CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM dbo.FMS_CashAdvanceAttachments attachment
                   WHERE attachment.CashAdvanceRequestId = r.CashAdvanceRequestId
                     AND attachment.RelativePath LIKE N'rfp/%'
               ) THEN 1
               ELSE 0
           END,
           @HasCashierReceipt = CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
                   WHERE receipt.CashAdvanceRequestId = r.CashAdvanceRequestId
               ) THEN 1
               ELSE 0
           END
    FROM dbo.FMS_CashAdvanceRequests r
    WHERE r.CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId = 4;

    IF @Amount IS NULL
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN 6
                ELSE 0
            END,
            RemainingAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN RemainingAmount
                ELSE COALESCE(NULLIF(@LiquidationBaseAmount, 0), @Amount)
            END,
            ReturnAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN ReturnAmount
                ELSE NULL
            END,
            ExcessAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN ExcessAmount
                ELSE NULL
            END,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'returned',
            @ApproverUserId,
            @AmountSpent,
            COALESCE(@Notes, 'Accounting returned the request for correction.')
        );

        RETURN;
    END

    IF ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' AND ISNULL(@HasRfpAttachment, 0) = 0
    BEGIN
        THROW 51017, 'RFP attachment is required before accounting approval.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = CASE
            WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision IS NULL THEN 5
            WHEN ISNULL(@ReturnAmount, 0) > 0 AND ISNULL(@HasCashierReceipt, 0) = 0 THEN 2
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 3
            ELSE 8
        END,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'approved_by_accounting', @ApproverUserId, @AmountSpent, @Notes);
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_CashierCloseLiquidation
    @CashAdvanceRequestId int,
    @CashierUserId int,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnAmount decimal(19,4);

    SELECT @ReturnAmount = ReturnAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId = 3
      AND EXISTS
      (
          SELECT 1
          FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
          WHERE receipt.CashAdvanceRequestId = @CashAdvanceRequestId
      );

    IF @ReturnAmount IS NULL
    BEGIN
        THROW 51011, 'Cash advance request is not ready for cashier liquidation closure.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET StatusId = 8,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'fully_liquidated',
        @CashierUserId,
        @ReturnAmount,
        COALESCE(@Notes, 'Cashier closed liquidation after final accounting approval.')
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceAttachments_GetById
    @AttachmentId int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT AttachmentId AS Id,
           COALESCE(OriginalFileName, FileName) AS OriginalFileName,
           RelativePath,
           COALESCE(ContentType, N'application/octet-stream') AS ContentType
    FROM dbo.FMS_CashAdvanceAttachments
    WHERE AttachmentId = @AttachmentId
      AND RelativePath IS NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceAcknowledgementReceipts_GetAttachmentById
    @ReceiptId int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReceiptId AS Id,
           AttachmentFileName AS OriginalFileName,
           AttachmentRelativePath AS RelativePath,
           COALESCE(AttachmentContentType, N'application/octet-stream') AS ContentType
    FROM dbo.FMS_CashAdvanceAcknowledgementReceipts
    WHERE ReceiptId = @ReceiptId
      AND AttachmentRelativePath IS NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceAcknowledgementReceipts_GetDepositSlipById
    @ReceiptId int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReceiptId AS Id,
           DepositSlipFileName AS OriginalFileName,
           DepositSlipRelativePath AS RelativePath,
           COALESCE(DepositSlipContentType, N'application/octet-stream') AS ContentType
    FROM dbo.FMS_CashAdvanceAcknowledgementReceipts
    WHERE ReceiptId = @ReceiptId
      AND DepositSlipRelativePath IS NOT NULL;
END
GO
