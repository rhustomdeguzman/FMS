USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

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
END;

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

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'StatusId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD StatusId int NULL;
END;
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'Status') IS NOT NULL
BEGIN
    UPDATE r
    SET StatusId = s.StatusId
    FROM dbo.FMS_CashAdvanceRequests r
    INNER JOIN dbo.FMS_CashAdvanceStatuses s ON s.StatusCode = r.Status
    WHERE r.StatusId IS NULL;
END;

UPDATE dbo.FMS_CashAdvanceRequests
SET StatusId = 0
WHERE StatusId IS NULL;

DECLARE @Sql nvarchar(max);
DECLARE @IndexName sysname;

DECLARE StatusIndexes CURSOR LOCAL FAST_FORWARD FOR
SELECT DISTINCT i.name
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests')
  AND c.name = N'Status'
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0;

OPEN StatusIndexes;
FETCH NEXT FROM StatusIndexes INTO @IndexName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'DROP INDEX ' + QUOTENAME(@IndexName) + N' ON dbo.FMS_CashAdvanceRequests;';
    EXEC sys.sp_executesql @Sql;
    FETCH NEXT FROM StatusIndexes INTO @IndexName;
END;

CLOSE StatusIndexes;
DEALLOCATE StatusIndexes;

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_Status' AND parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT CK_CashAdvanceRequests_Status;
END;

DECLARE @DefaultName sysname;

SELECT @DefaultName = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests')
  AND c.name = N'Status';

IF @DefaultName IS NOT NULL
BEGIN
    SET @Sql = N'ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT ' + QUOTENAME(@DefaultName) + N';';
    EXEC sys.sp_executesql @Sql;
END;

ALTER TABLE dbo.FMS_CashAdvanceRequests ALTER COLUMN StatusId int NOT NULL;

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
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CashAdvanceRequests_Statuses' AND parent_object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests
    ADD CONSTRAINT FK_CashAdvanceRequests_Statuses FOREIGN KEY (StatusId) REFERENCES dbo.FMS_CashAdvanceStatuses(StatusId);
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'Status') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP COLUMN Status;
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_StatusDepartment' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    CREATE INDEX IX_CashAdvanceRequests_StatusDepartment ON dbo.FMS_CashAdvanceRequests(StatusId, Department);
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceRequests_PendingTransferTo' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceRequests'))
BEGIN
    CREATE INDEX IX_CashAdvanceRequests_PendingTransferTo ON dbo.FMS_CashAdvanceRequests(PendingTransferToUserId, StatusId)
    WHERE PendingTransferToUserId IS NOT NULL;
END;

COMMIT TRANSACTION;
GO
