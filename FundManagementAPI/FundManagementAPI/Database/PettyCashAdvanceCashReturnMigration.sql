-- Run against FMS before deploying the updated API and website.
-- Preserve installed workflow procedures; do not move existing requests automatically.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_DepartmentDecision'));
IF @Definition IS NULL THROW 51220, 'Department decision procedure is missing.', 1;
IF @Definition NOT LIKE N'%PettyCashAdvanceCashReturnRouting%'
BEGIN
    DECLARE @Anchor nvarchar(300) = N'SET @ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END;';
    IF CHARINDEX(@Anchor, @Definition) = 0
        THROW 51221, 'Unrecognized department decision procedure. Review before applying.', 1;
    SET @Definition = REPLACE(@Definition, @Anchor, @Anchor + N'
    -- PettyCashAdvanceCashReturnRouting
    IF @RequestType = N''petty_cash_advance'' AND @CustodianUserId IS NOT NULL AND @ReturnAmount > 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 13, RemainingAmount = 0, ReturnAmount = @ReturnAmount,
            ExcessAmount = NULL, UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, ''approved_by_department_head'', @ApproverUserId, @AmountSpent,
                COALESCE(@Notes, ''Department approved liquidation. Return unspent petty cash to the custodian.''));
        RETURN;
    END;');
    SET @Definition = N'ALTER ' + SUBSTRING(@Definition, CHARINDEX(N'PROCEDURE', UPPER(@Definition)), LEN(@Definition));
    EXEC sys.sp_executesql @Definition;
END;
GO
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_PettyCashRequests_CustodianDecision'));
IF @Definition IS NULL THROW 51222, 'Custodian decision procedure is missing.', 1;
IF @Definition NOT LIKE N'%PettyCashAdvanceCashReceived%'
BEGIN
    IF EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.sp_PettyCashRequests_CustodianDecision') AND name = N'@ReturnedAmount')
        THROW 51223, 'ReturnedAmount already exists. Review the installed procedure.', 1;
    DECLARE @Parameter nvarchar(100) = N'@Notes nvarchar(1000) = NULL';
    DECLARE @Anchor nvarchar(100) = N'SELECT @StatusId = StatusId,';
    IF CHARINDEX(@Parameter, @Definition) = 0 OR CHARINDEX(@Anchor, @Definition) = 0
        THROW 51224, 'Unrecognized custodian decision procedure. Review before applying.', 1;
    SET @Definition = REPLACE(@Definition, @Parameter, @Parameter + N', @ReturnedAmount decimal(19,4) = NULL');
    SET @Definition = REPLACE(@Definition, @Anchor, N'
    -- PettyCashAdvanceCashReceived: record physical cash and close in one transaction.
    IF @Approved = 1 AND (@ReturnedAmount IS NOT NULL OR EXISTS (
        SELECT 1 FROM dbo.FMS_CashAdvanceRequests
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId AND RequestType = N''petty_cash_advance''
          AND StatusId = 13 AND ReturnAmount > 0))
    BEGIN
        SET XACT_ABORT ON;
        BEGIN TRY
            BEGIN TRANSACTION;
            DECLARE @ExpectedCash decimal(19,4), @SpentCash decimal(19,4);
            SELECT @ExpectedCash = COALESCE(LiquidationBaseAmount, Amount) - AmountSpent,
                   @SpentCash = AmountSpent
            FROM dbo.FMS_CashAdvanceRequests WITH (UPDLOCK, HOLDLOCK)
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId
              AND CustodianUserId = @CustodianUserId AND RequestType = N''petty_cash_advance''
              AND StatusId = 13 AND ReturnAmount > 0
              AND EXISTS (SELECT 1 FROM dbo.vw_FMS_AppUsers
                          WHERE UserId = @CustodianUserId AND Role = N''custodian'' AND IsActive = 1);
            IF @ExpectedCash IS NULL OR @ExpectedCash <= 0
                THROW 51225, ''Petty cash advance is not awaiting this custodian cash return approval.'', 1;
            IF @ReturnedAmount IS NULL OR @ReturnedAmount <= 0 OR ABS(@ReturnedAmount - @ExpectedCash) >= 0.005
                THROW 51226, ''Cash received must match the expected cash return.'', 1;
            UPDATE dbo.FMS_CashAdvanceRequests
            SET StatusId = 8, RemainingAmount = 0, ReturnAmount = @ReturnedAmount, UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
                (@CashAdvanceRequestId, ''acknowledged'', @CustodianUserId, @ReturnedAmount, ''Custodian received the unspent petty cash advance balance.''),
                (@CashAdvanceRequestId, ''approved_by_custodian'', @CustodianUserId, @SpentCash, @Notes),
                (@CashAdvanceRequestId, ''fully_liquidated'', @CustodianUserId, @SpentCash, ''Petty cash advance closed after custodian received excess cash.'');
            COMMIT TRANSACTION;
            RETURN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;
    END;
    ' + @Anchor);
    SET @Definition = N'ALTER ' + SUBSTRING(@Definition, CHARINDEX(N'PROCEDURE', UPPER(@Definition)), LEN(@Definition));
    EXEC sys.sp_executesql @Definition;
END;
GO
