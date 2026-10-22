USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

DECLARE @Sql nvarchar(max);
DECLARE @TableName sysname;
DECLARE @OldColumnName sysname;
DECLARE @NewColumnName sysname;
DECLARE @FullTableName nvarchar(300);
DECLARE @DefaultName sysname;
DECLARE @ColumnDefinition nvarchar(100);
DECLARE @HasDefault bit;

DECLARE RenameColumns CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, OldColumnName, NewColumnName
FROM
(
    VALUES
        (N'FMS_AppUsers', N'UpdatedAtUtc', N'UpdatedAt'),
        (N'FMS_CashAdvanceRequests', N'LiquidatedAtUtc', N'LiquidatedAt'),
        (N'FMS_CashAdvanceRequests', N'UpdatedAtUtc', N'UpdatedAt'),
        (N'FMS_CashAdvanceAttachments', N'UploadedAtUtc', N'UploadedAt'),
        (N'FMS_CashAdvanceTransfers', N'RequestedAtUtc', N'RequestedAt'),
        (N'FMS_CashAdvanceTransfers', N'RespondedAtUtc', N'RespondedAt')
) v(TableName, OldColumnName, NewColumnName);

OPEN RenameColumns;
FETCH NEXT FROM RenameColumns INTO @TableName, @OldColumnName, @NewColumnName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @FullTableName = N'dbo.' + @TableName;

    IF COL_LENGTH(@FullTableName, @OldColumnName) IS NOT NULL
       AND COL_LENGTH(@FullTableName, @NewColumnName) IS NULL
    BEGIN
        SET @Sql = N'dbo.' + QUOTENAME(@TableName) + N'.' + QUOTENAME(@OldColumnName);
        EXEC sys.sp_rename @Sql, @NewColumnName, N'COLUMN';
    END;

    FETCH NEXT FROM RenameColumns INTO @TableName, @OldColumnName, @NewColumnName;
END;

CLOSE RenameColumns;
DEALLOCATE RenameColumns;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceTransfers_ToUserStatus' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceTransfers'))
BEGIN
    DROP INDEX IX_CashAdvanceTransfers_ToUserStatus ON dbo.FMS_CashAdvanceTransfers;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'LiquidatedAt') IS NOT NULL
BEGIN
    SET @Sql = N'
        UPDATE r
        SET LiquidatedAt = DATEADD(HOUR, 8, r.LiquidatedAt)
        FROM dbo.FMS_CashAdvanceRequests r
        WHERE r.LiquidatedAt IS NOT NULL
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = r.CashAdvanceRequestId
                AND h.Action = ''liquidation_submitted''
                AND ABS(DATEDIFF(MINUTE, DATEADD(HOUR, 8, r.LiquidatedAt), h.AuditDate)) <= 90
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = r.CashAdvanceRequestId
                AND h.Action = ''liquidation_submitted''
                AND ABS(DATEDIFF(MINUTE, r.LiquidatedAt, h.AuditDate)) <= 90
          );';
    EXEC sys.sp_executesql @Sql;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'UpdatedAt') IS NOT NULL
BEGIN
    SET @Sql = N'
        UPDATE r
        SET UpdatedAt = DATEADD(HOUR, 8, r.UpdatedAt)
        FROM dbo.FMS_CashAdvanceRequests r
        WHERE r.UpdatedAt IS NOT NULL
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = r.CashAdvanceRequestId
                AND ABS(DATEDIFF(MINUTE, DATEADD(HOUR, 8, r.UpdatedAt), h.AuditDate)) <= 90
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = r.CashAdvanceRequestId
                AND ABS(DATEDIFF(MINUTE, r.UpdatedAt, h.AuditDate)) <= 90
          );';
    EXEC sys.sp_executesql @Sql;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceAttachments', N'UploadedAt') IS NOT NULL
BEGIN
    SET @Sql = N'
        UPDATE a
        SET UploadedAt = DATEADD(HOUR, 8, a.UploadedAt)
        FROM dbo.FMS_CashAdvanceAttachments a
        WHERE EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = a.CashAdvanceRequestId
                AND ABS(DATEDIFF(MINUTE, DATEADD(HOUR, 8, a.UploadedAt), h.AuditDate)) <= 90
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = a.CashAdvanceRequestId
                AND ABS(DATEDIFF(MINUTE, a.UploadedAt, h.AuditDate)) <= 90
          );';
    EXEC sys.sp_executesql @Sql;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceTransfers', N'RespondedAt') IS NOT NULL
BEGIN
    SET @Sql = N'
        UPDATE t
        SET RespondedAt = DATEADD(HOUR, 8, t.RespondedAt)
        FROM dbo.FMS_CashAdvanceTransfers t
        WHERE t.RespondedAt IS NOT NULL
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = t.CashAdvanceRequestId
                AND h.Action IN (''transfer_acknowledged'', ''transfer_denied'')
                AND ABS(DATEDIFF(MINUTE, DATEADD(HOUR, 8, t.RespondedAt), h.AuditDate)) <= 90
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceHistory h
              WHERE h.CashAdvanceRequestId = t.CashAdvanceRequestId
                AND h.Action IN (''transfer_acknowledged'', ''transfer_denied'')
                AND ABS(DATEDIFF(MINUTE, t.RespondedAt, h.AuditDate)) <= 90
          );';
    EXEC sys.sp_executesql @Sql;
END;

DECLARE DateColumns CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, ColumnName, ColumnDefinition, DefaultName, HasDefault
FROM
(
    VALUES
        (N'FMS_AppUsers', N'AuditDate', N'datetime NOT NULL', N'DF_AppUsers_AuditDate', CONVERT(bit, 1)),
        (N'FMS_AppUsers', N'UpdatedAt', N'datetime NULL', NULL, CONVERT(bit, 0)),
        (N'FMS_CashAdvanceRequests', N'LiquidatedAt', N'datetime NULL', NULL, CONVERT(bit, 0)),
        (N'FMS_CashAdvanceRequests', N'AuditDate', N'datetime NOT NULL', N'DF_CashAdvanceRequests_AuditDate', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceRequests', N'UpdatedAt', N'datetime NULL', NULL, CONVERT(bit, 0)),
        (N'FMS_CashAdvanceAttachments', N'UploadedAt', N'datetime NOT NULL', N'DF_CashAdvanceAttachments_UploadedAt', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceRequests_Dtl', N'AuditDate', N'datetime NOT NULL', N'DF_CashAdvanceRequests_Dtl_AuditDate', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceAcknowledgementReceipts', N'DepositDate', N'datetime NULL', NULL, CONVERT(bit, 0)),
        (N'FMS_CashAdvanceAcknowledgementReceipts', N'AuditDate', N'datetime NOT NULL', N'DF_CashAdvanceAcknowledgementReceipts_AuditDate', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceHistory', N'AuditDate', N'datetime NOT NULL', N'DF_CashAdvanceHistory_AuditDate', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceTransfers', N'RequestedAt', N'datetime NOT NULL', N'DF_CashAdvanceTransfers_RequestedAt', CONVERT(bit, 1)),
        (N'FMS_CashAdvanceTransfers', N'RespondedAt', N'datetime NULL', NULL, CONVERT(bit, 0))
) v(TableName, ColumnName, ColumnDefinition, DefaultName, HasDefault);

OPEN DateColumns;
FETCH NEXT FROM DateColumns INTO @TableName, @NewColumnName, @ColumnDefinition, @DefaultName, @HasDefault;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @FullTableName = N'dbo.' + @TableName;

    IF COL_LENGTH(@FullTableName, @NewColumnName) IS NOT NULL
    BEGIN
        SET @Sql = NULL;

        SELECT @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' DROP CONSTRAINT ' + QUOTENAME(dc.name)
        FROM sys.default_constraints dc
        INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
        WHERE dc.parent_object_id = OBJECT_ID(@FullTableName)
          AND c.name = @NewColumnName;

        IF @Sql IS NOT NULL
        BEGIN
            EXEC sys.sp_executesql @Sql;
        END;

        SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
            N' ALTER COLUMN ' + QUOTENAME(@NewColumnName) + N' ' + @ColumnDefinition;
        EXEC sys.sp_executesql @Sql;

        IF @HasDefault = 1
        BEGIN
            SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
                N' ADD CONSTRAINT ' + QUOTENAME(@DefaultName) +
                N' DEFAULT (GETDATE()) FOR ' + QUOTENAME(@NewColumnName);
            EXEC sys.sp_executesql @Sql;
        END;
    END;

    FETCH NEXT FROM DateColumns INTO @TableName, @NewColumnName, @ColumnDefinition, @DefaultName, @HasDefault;
END;

CLOSE DateColumns;
DEALLOCATE DateColumns;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CashAdvanceTransfers_ToUserStatus' AND object_id = OBJECT_ID(N'dbo.FMS_CashAdvanceTransfers'))
BEGIN
    SET @Sql = N'CREATE INDEX IX_CashAdvanceTransfers_ToUserStatus ON dbo.FMS_CashAdvanceTransfers(ToUserId, Status, RequestedAt);';
    EXEC sys.sp_executesql @Sql;
END;

COMMIT TRANSACTION;
GO
