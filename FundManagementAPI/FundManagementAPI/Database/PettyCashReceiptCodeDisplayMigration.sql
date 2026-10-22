USE [FMS];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DECLARE @ProcedureName sysname = N'sp_CashAdvanceRequests_GetForUser';
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@ProcedureName)));
DECLARE @ProcedureIndex int;

IF @Definition IS NULL
BEGIN
    THROW 51110, 'sp_CashAdvanceRequests_GetForUser was not found.', 1;
END;

IF @Definition NOT LIKE N'%natureOfExpenseCode%'
BEGIN
    SET @Definition = REPLACE(
        @Definition,
        N'pc.NatureOfExpense AS natureOfExpense,
                       pc.CostCenter AS costCenter,',
        N'pc.NatureOfExpense AS natureOfExpenseCode,
                       COALESCE(pettyExpenseTypeInfo.ExpenseName, pc.NatureOfExpense, N'''') AS natureOfExpense,
                       pc.CostCenter AS costCenterCode,
                       COALESCE(pettyProfitCenterInfo.OcrName, pc.CostCenter, N'''') AS costCenter,');

    SET @Definition = REPLACE(
        @Definition,
        N'FROM dbo.FMS_PettyCashReceiptDetails pc
                WHERE pc.CashAdvanceRequestId = r.CashAdvanceRequestId',
        N'FROM dbo.FMS_PettyCashReceiptDetails pc
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT)), N'''') AS ExpenseName
                    FROM dbo.vw_FMS_ExpenseType expenseTypeView
                    WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), expenseTypeView.Code) COLLATE DATABASE_DEFAULT)), N'''') = pc.NatureOfExpense
                    ORDER BY LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT))
                ) pettyExpenseTypeInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT)), N'''') AS OcrName
                    FROM FineReport..vwProfitCenters profitCenterView
                    WHERE NULLIF(LTRIM(RTRIM(profitCenterView.OcrCode COLLATE DATABASE_DEFAULT)), N'''') = pc.CostCenter
                    ORDER BY LTRIM(RTRIM(profitCenterView.OcrName COLLATE DATABASE_DEFAULT))
                ) pettyProfitCenterInfo
                WHERE pc.CashAdvanceRequestId = r.CashAdvanceRequestId');

    IF @Definition NOT LIKE N'%natureOfExpenseCode%'
       OR @Definition NOT LIKE N'%pettyProfitCenterInfo%'
    BEGIN
        THROW 51111, 'The petty-cash receipt detail block was not found in sp_CashAdvanceRequests_GetForUser.', 1;
    END;

    SET @ProcedureIndex = PATINDEX(N'%PROCEDURE%', @Definition);

    IF @ProcedureIndex <= 0
    BEGIN
        THROW 51112, 'Could not locate procedure keyword in sp_CashAdvanceRequests_GetForUser definition.', 1;
    END;

    SET @Definition = STUFF(@Definition, 1, @ProcedureIndex - 1, N'ALTER ');

    EXEC sys.sp_executesql @Definition;
END;
GO
