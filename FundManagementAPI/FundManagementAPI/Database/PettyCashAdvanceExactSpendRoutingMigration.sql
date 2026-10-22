-- Run after PettyCashAdvanceCashReturnMigration.sql in FMS.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_DepartmentDecision'));
DECLARE @OldRule nvarchar(300) = N'IF @RequestType = N''petty_cash_advance'' AND @CustodianUserId IS NOT NULL AND @ReturnAmount > 0';
DECLARE @NewRule nvarchar(300) = N'IF @RequestType = N''petty_cash_advance'' AND @CustodianUserId IS NOT NULL AND @AmountSpent <= @LiquidationBaseAmount';
IF @Definition IS NULL OR @Definition NOT LIKE N'%PettyCashAdvanceCashReturnRouting%'
    THROW 51230, 'Install PettyCashAdvanceCashReturnMigration.sql first.', 1;
IF CHARINDEX(@NewRule, @Definition) = 0
BEGIN
    IF CHARINDEX(@OldRule, @Definition) = 0
        THROW 51231, 'Unrecognized petty cash advance routing. Review before applying.', 1;
    SET @Definition = REPLACE(@Definition, @OldRule, @NewRule);
    SET @Definition = REPLACE(@Definition,
        N'Department approved liquidation. Return unspent petty cash to the custodian.',
        N'Department approved liquidation. Routed to custodian for final review and any cash return.');
    SET @Definition = N'ALTER ' + SUBSTRING(@Definition, CHARINDEX(N'PROCEDURE', UPPER(@Definition)), LEN(@Definition));
    EXEC sys.sp_executesql @Definition;
END;
GO
