SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

UPDATE rfp
SET RequestorUserId = COALESCE(parent.CurrentOwnerUserId, parent.RequestorUserId),
    CurrentOwnerUserId = COALESCE(parent.CurrentOwnerUserId, parent.RequestorUserId),
    Department = parent.Department,
    UpdatedAt = GETDATE()
FROM dbo.FMS_CashAdvanceRequests rfp
INNER JOIN dbo.FMS_CashAdvanceRequests parent
    ON parent.CashAdvanceRequestId = rfp.OriginalCashAdvanceRequestId
WHERE rfp.Status = 'rfp_created'
  AND rfp.OriginalCashAdvanceRequestId IS NOT NULL
  AND (
      rfp.RequestorUserId <> COALESCE(parent.CurrentOwnerUserId, parent.RequestorUserId)
      OR COALESCE(rfp.CurrentOwnerUserId, rfp.RequestorUserId) <> COALESCE(parent.CurrentOwnerUserId, parent.RequestorUserId)
  );
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
