SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_CustodianCreateReceipt
    @CashAdvanceRequestId int,
    @CustodianUserId int,
    @ReceiptNumber nvarchar(50),
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnAmount decimal(19,4);

    SELECT @ReturnAmount = ReturnAmount
    FROM dbo.FMS_CashAdvanceRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND CustodianUserId = @CustodianUserId
      AND StatusId = 13
      AND RequestType IN (N'petty_cash', N'petty_cash_advance')
      AND ReturnAmount > 0
      AND EXISTS
      (
          SELECT 1
          FROM dbo.vw_FMS_AppUsers custodian
          WHERE custodian.UserId = @CustodianUserId
            AND custodian.Role = N'custodian'
            AND custodian.IsActive = 1
      );

    IF @ReturnAmount IS NULL
    BEGIN
        RAISERROR('Petty cash request is not waiting for custodian return acknowledgement.', 16, 1);
        RETURN;
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
            CreatedByUserId = @CustodianUserId,
            Notes = @Notes,
            AuditDate = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceAcknowledgementReceipts
            (CashAdvanceRequestId, ReceiptNumber, ReturnAmount, CreatedByUserId, Notes)
        VALUES
            (@CashAdvanceRequestId, @ReceiptNumber, @ReturnAmount, @CustodianUserId, @Notes);
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'acknowledged',
        @CustodianUserId,
        @ReturnAmount,
        COALESCE(@Notes, 'Custodian acknowledged returned excess petty cash and printed the acknowledgement receipt.')
    );
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
    DECLARE @ReturnAmount decimal(19,4);
    DECLARE @Department nvarchar(100);
    DECLARE @Purpose nvarchar(500);
    DECLARE @RequestNumber nvarchar(50);

    SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @RequestorUserId = RequestorUserId,
           @Amount = Amount,
           @AmountSpent = AmountSpent,
           @ReturnAmount = ReturnAmount,
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

        IF ISNULL(@ReturnAmount, 0) > 0
           AND NOT EXISTS
           (
               SELECT 1
               FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
               WHERE receipt.CashAdvanceRequestId = @CashAdvanceRequestId
           )
        BEGIN
            RAISERROR('Returned excess petty cash must be acknowledged by the custodian before approval.', 16, 1);
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
