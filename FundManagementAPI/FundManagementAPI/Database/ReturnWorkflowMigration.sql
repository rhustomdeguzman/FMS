SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_Status')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT CK_CashAdvanceRequests_Status;
END
GO

ALTER TABLE dbo.FMS_CashAdvanceRequests
ADD CONSTRAINT CK_CashAdvanceRequests_Status CHECK (Status IN
(
    'pending_liquidation',
    'pending_department_approval',
    'pending_cashier_return',
    'pending_cashier_closure',
    'pending_accounting_review',
    'pending_rfp_department_approval',
    'partially_liquidated',
    'fully_liquidated',
    'rfp_created',
    'rejected'
));
GO

UPDATE r
SET Status = 'pending_accounting_review',
    UpdatedAt = GETDATE()
FROM dbo.FMS_CashAdvanceRequests r
WHERE r.Status = 'pending_cashier_return'
  AND ISNULL(r.ReturnAmount, 0) > 0
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
      WHERE receipt.CashAdvanceRequestId = r.CashAdvanceRequestId
  )
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.FMS_CashAdvanceHistory history
      WHERE history.CashAdvanceRequestId = r.CashAdvanceRequestId
        AND history.Action = 'approved_by_accounting'
  );
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
           (
               SELECT TOP (1)
                      receipt.ReceiptId AS receiptId,
                      receipt.ReceiptNumber AS receiptNumber,
                      receipt.ReturnAmount AS returnAmount,
                      receipt.AttachmentFileName AS attachmentFileName,
                      receipt.AttachmentContentType AS attachmentContentType,
                      receipt.AttachmentFileSizeBytes AS attachmentFileSizeBytes,
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

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_DepartmentDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status nvarchar(50);
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

    SELECT @Status = Status,
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

    IF @Status IS NULL
    BEGIN
        RETURN;
    END

    IF @Status = 'pending_rfp_department_approval'
    BEGIN
        IF @Approved = 1 AND ISNULL(@ExcessAmount, 0) > 0
        BEGIN
            SET @RfpRequestNumber = CONCAT(@RequestNumber, '-RFP-', @CashAdvanceRequestId);

            INSERT INTO dbo.FMS_CashAdvanceRequests
                (OriginalCashAdvanceRequestId, RequestNumber, RequestorUserId, CurrentOwnerUserId, Department, Amount, RemainingAmount, AmountSpent, ExcessAmount, Purpose, Status)
            VALUES
                (@CashAdvanceRequestId, @RfpRequestNumber, @CurrentOwnerUserId, @CurrentOwnerUserId, @Department, @ExcessAmount, 0, @ExcessAmount, @ExcessAmount, CONCAT('RFP for excess spend: ', @Purpose), 'rfp_created');

            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'fully_liquidated',
                RfpRequestNumber = @RfpRequestNumber,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES (@CashAdvanceRequestId, 'rfp_created', @ApproverUserId, @ExcessAmount, @Notes);
        END
        ELSE
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'fully_liquidated',
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES (@CashAdvanceRequestId, 'rejected', @ApproverUserId, @ExcessAmount, @Notes);
        END

        RETURN;
    END

    IF @Status <> 'pending_department_approval'
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET Status = 'rejected',
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'rejected', @ApproverUserId, @AmountSpent, @Notes);

        RETURN;
    END

    SET @ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END;
    SET @ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END;

    UPDATE dbo.FMS_CashAdvanceRequests
    SET Status = CASE
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 'pending_cashier_return'
            ELSE 'pending_accounting_review'
        END,
        ReturnAmount = NULLIF(@ReturnAmount, 0),
        ExcessAmount = NULLIF(@ExcessAmount, 0),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'approved_by_department_head', @ApproverUserId, @AmountSpent, @Notes);
END
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
    DECLARE @HasCashierReceipt bit;

    SELECT @ExcessAmount = ExcessAmount,
           @ReturnAmount = ReturnAmount,
           @Amount = Amount,
           @AmountSpent = AmountSpent,
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
      AND Status = 'pending_accounting_review';

    IF @Amount IS NULL
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET Status = 'rejected',
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'rejected', @ApproverUserId, @AmountSpent, @Notes);

        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET Status = CASE
            WHEN ISNULL(@ExcessAmount, 0) > 0 THEN 'pending_rfp_department_approval'
            WHEN ISNULL(@ReturnAmount, 0) > 0 AND ISNULL(@HasCashierReceipt, 0) = 0 THEN 'pending_cashier_return'
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 'pending_cashier_closure'
            ELSE 'fully_liquidated'
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
      AND Status = 'pending_cashier_closure'
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
    SET Status = 'fully_liquidated',
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
