USE [FMS];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DECLARE @GetForUserProcedureName sysname = N'sp_CashAdvanceRequests_GetForUser';
DECLARE @GetForUserDefinition nvarchar(max) =
    OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@GetForUserProcedureName)));
DECLARE @GetForUserProcedureIndex int;

IF @GetForUserDefinition IS NULL
BEGIN
    THROW 51120, 'sp_CashAdvanceRequests_GetForUser was not found.', 1;
END;

IF @GetForUserDefinition LIKE N'%WHEN r.RequestType IN (N''petty_cash'', N''petty_cash_advance'') THEN N''Petty Cash''%'
   OR EXISTS
   (
       SELECT 1
       FROM sys.sql_modules
       WHERE [object_id] = OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@GetForUserProcedureName))
         AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0)
   )
BEGIN
    SET @GetForUserDefinition = REPLACE(
        @GetForUserDefinition,
        N'WHEN r.RequestType IN (N''petty_cash'', N''petty_cash_advance'') THEN N''Petty Cash''',
        N'WHEN r.RequestType IN (N''petty_cash'', N''petty_cash_advance'') AND r.CustodianUserId IS NOT NULL THEN N''Petty Cash''');

    SET @GetForUserProcedureIndex = PATINDEX(N'%PROCEDURE%', @GetForUserDefinition);

    IF @GetForUserProcedureIndex <= 0
    BEGIN
        THROW 51121, 'Could not locate procedure keyword in sp_CashAdvanceRequests_GetForUser definition.', 1;
    END;

    SET @GetForUserDefinition = STUFF(@GetForUserDefinition, 1, @GetForUserProcedureIndex - 1, N'ALTER ');

    EXEC sys.sp_executesql @GetForUserDefinition;
END;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DECLARE @DepartmentProcedureName sysname = N'sp_CashAdvanceRequests_DepartmentDecision';
DECLARE @DepartmentDefinition nvarchar(max) =
    OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@DepartmentProcedureName)));
DECLARE @DepartmentProcedureIndex int;

IF @DepartmentDefinition IS NULL
BEGIN
    THROW 51122, 'sp_CashAdvanceRequests_DepartmentDecision was not found.', 1;
END;

IF @DepartmentDefinition NOT LIKE N'%@UsesPettyCashWorkflow%'
   OR EXISTS
   (
       SELECT 1
       FROM sys.sql_modules
       WHERE [object_id] = OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@DepartmentProcedureName))
         AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0)
   )
BEGIN
    SET @DepartmentDefinition = REPLACE(
        @DepartmentDefinition,
        N'DECLARE @RequestType nvarchar(50);
    DECLARE @AmountSpent decimal(19,4);',
        N'DECLARE @RequestType nvarchar(50);
    DECLARE @CustodianUserId int;
    DECLARE @UsesPettyCashWorkflow bit = 0;
    DECLARE @AmountSpent decimal(19,4);');

    SET @DepartmentDefinition = REPLACE(
        @DepartmentDefinition,
        N'SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @AmountSpent = AmountSpent,',
        N'SELECT @StatusId = StatusId,
           @RequestType = RequestType,
           @CustodianUserId = CustodianUserId,
           @AmountSpent = AmountSpent,');

    SET @DepartmentDefinition = REPLACE(
        @DepartmentDefinition,
        N'IF @StatusId IS NULL
    BEGIN
        RETURN;
    END

    IF @RequestType IN (N''petty_cash'', N''petty_cash_advance'') AND @StatusId = 1 AND @AmountSpent IS NULL',
        N'IF @StatusId IS NULL
    BEGIN
        RETURN;
    END

    SET @UsesPettyCashWorkflow = CASE
        WHEN @RequestType IN (N''petty_cash'', N''petty_cash_advance'') AND @CustodianUserId IS NOT NULL THEN 1
        ELSE 0
    END;

    IF @UsesPettyCashWorkflow = 1 AND @StatusId = 1 AND @AmountSpent IS NULL');

    SET @DepartmentDefinition = REPLACE(
        @DepartmentDefinition,
        N'IF @RequestType IN (N''petty_cash'', N''petty_cash_advance'')
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 13,',
        N'IF @UsesPettyCashWorkflow = 1
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET StatusId = 13,');

    IF @DepartmentDefinition NOT LIKE N'%@UsesPettyCashWorkflow%'
       OR @DepartmentDefinition NOT LIKE N'%@CustodianUserId = CustodianUserId%'
    BEGIN
        THROW 51123, 'The department decision petty-cash routing block was not found.', 1;
    END;

    SET @DepartmentProcedureIndex = PATINDEX(N'%PROCEDURE%', @DepartmentDefinition);

    IF @DepartmentProcedureIndex <= 0
    BEGIN
        THROW 51124, 'Could not locate procedure keyword in sp_CashAdvanceRequests_DepartmentDecision definition.', 1;
    END;

    SET @DepartmentDefinition = STUFF(@DepartmentDefinition, 1, @DepartmentProcedureIndex - 1, N'ALTER ');

    EXEC sys.sp_executesql @DepartmentDefinition;
END;
GO
