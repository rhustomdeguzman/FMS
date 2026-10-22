USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

DECLARE @TableName sysname;
DECLARE @DefaultName sysname;
DECLARE @FullTableName nvarchar(300);
DECLARE @Sql nvarchar(max);

DECLARE AuditDateColumns CURSOR LOCAL FAST_FORWARD FOR
SELECT TableName, DefaultName
FROM
(
    VALUES
        (N'FMS_AppUsers', N'DF_AppUsers_AuditDate'),
        (N'FMS_CashAdvanceRequests', N'DF_CashAdvanceRequests_AuditDate'),
        (N'FMS_CashAdvanceRequests_Dtl', N'DF_CashAdvanceRequests_Dtl_AuditDate'),
        (N'FMS_CashAdvanceAcknowledgementReceipts', N'DF_CashAdvanceAcknowledgementReceipts_AuditDate'),
        (N'FMS_CashAdvanceHistory', N'DF_CashAdvanceHistory_AuditDate')
) v(TableName, DefaultName);

OPEN AuditDateColumns;
FETCH NEXT FROM AuditDateColumns INTO @TableName, @DefaultName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @FullTableName = N'dbo.' + @TableName;

    IF COL_LENGTH(@FullTableName, N'CreatedAtUtc') IS NOT NULL
    BEGIN
        SET @Sql = N'dbo.' + QUOTENAME(@TableName) + N'.[CreatedAtUtc]';
        EXEC sys.sp_rename @Sql, N'AuditDate', N'COLUMN';
    END;

    IF COL_LENGTH(@FullTableName, N'AuditDate') IS NOT NULL
    BEGIN
        SET @Sql = NULL;

        SELECT @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' DROP CONSTRAINT ' + QUOTENAME(dc.name)
        FROM sys.default_constraints dc
        INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
        WHERE dc.parent_object_id = OBJECT_ID(@FullTableName)
          AND c.name = N'AuditDate';

        IF @Sql IS NOT NULL
        BEGIN
            EXEC sys.sp_executesql @Sql;
        END;

        SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
            N' ADD CONSTRAINT ' + QUOTENAME(@DefaultName) +
            N' DEFAULT (GETDATE()) FOR [AuditDate]';
        EXEC sys.sp_executesql @Sql;
    END;

    FETCH NEXT FROM AuditDateColumns INTO @TableName, @DefaultName;
END;

CLOSE AuditDateColumns;
DEALLOCATE AuditDateColumns;

COMMIT TRANSACTION;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_GetForUser
    @UserId int,
    @Role nvarchar(50),
    @Department nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.CashAdvanceRequestId,
           r.OriginalCashAdvanceRequestId,
           r.RequestNumber,
           r.RfpRequestNumber,
           r.Amount,
           COALESCE(r.RemainingAmount, CASE WHEN r.Status IN ('pending_liquidation', 'partially_liquidated') THEN r.Amount ELSE 0 END) AS RemainingAmount,
           r.AmountSpent,
           r.ReturnAmount,
           r.ExcessAmount,
           r.Purpose,
           r.Department,
           r.Status,
           r.RequestorUserId,
           u.DisplayName AS RequestorName,
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
                       d.Vendor AS vendor,
                       d.[Description] AS description,
                       d.Project AS project,
                       d.ProfitCenter AS profitCenter,
                       d.Amount AS amount,
                       d.InvoiceRef AS invoiceRef,
                       d.ExpenseType AS expenseType,
                       d.AuditDate AS auditDate
                FROM dbo.FMS_CashAdvanceRequests_Dtl d
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
    INNER JOIN dbo.FMS_AppUsers u ON u.UserId = r.RequestorUserId
    INNER JOIN dbo.FMS_AppUsers cu ON cu.UserId = COALESCE(r.CurrentOwnerUserId, r.RequestorUserId)
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
        EXISTS
        (
            SELECT 1
            FROM dbo.FMS_CashAdvanceTransfers accessTransfer
            WHERE accessTransfer.CashAdvanceRequestId = r.CashAdvanceRequestId
              AND accessTransfer.Status = 'pending'
              AND accessTransfer.ToUserId = @UserId
        )
        OR (@Role = 'requestor' AND (r.RequestorUserId = @UserId OR COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId))
        OR (@Role = 'department_head' AND COALESCE(r.CurrentOwnerUserId, r.RequestorUserId) = @UserId)
        OR (@Role = 'department_head' AND r.Department = @Department AND r.Status IN ('pending_liquidation', 'partially_liquidated', 'pending_department_approval', 'pending_rfp_department_approval'))
        OR (@Role = 'cashier' AND
            (
                r.Status IN ('pending_cashier_return', 'pending_cashier_closure')
                OR EXISTS
                (
                    SELECT 1
                    FROM dbo.FMS_CashAdvanceAcknowledgementReceipts cashierReceipt
                    WHERE cashierReceipt.CashAdvanceRequestId = r.CashAdvanceRequestId
                )
            ))
        OR (@Role = 'accounting')
    ORDER BY r.AuditDate DESC, r.CashAdvanceRequestId DESC;
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
      AND Status = 'pending_cashier_return';

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
    SET Status = CASE
            WHEN @DepositSlipRelativePath IS NULL THEN 'pending_cashier_return'
            ELSE 'pending_accounting_review'
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
            WHEN @DepositSlipRelativePath IS NULL THEN COALESCE(@Notes, 'Cashier saved acknowledgement receipt as draft. Deposit slip pending.')
            ELSE COALESCE(@Notes, 'Cashier uploaded deposit slip and sent acknowledgement receipt to accounting.')
        END
    );
END
GO
