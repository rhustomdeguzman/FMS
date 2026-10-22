USE [FMS];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DECLARE @ProcedureName sysname = N'sp_CashAdvanceRequests_GetForUser';
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@ProcedureName)));
DECLARE @ProcedureIndex int;
DECLARE @Changed bit = 0;

IF @Definition IS NULL
BEGIN
    THROW 51130, 'sp_CashAdvanceRequests_GetForUser was not found.', 1;
END;

IF @Definition LIKE N'%bp.BP_Name%'
BEGIN
    SET @Definition = REPLACE(
        @Definition,
        N'COALESCE(NULLIF(LTRIM(RTRIM(bp.BP_Name)), N''''), d.VendorCode, N'''') AS vendor,',
        N'COALESCE(vendorInfo.VendorName, d.VendorCode, N'''') AS vendor,');

    SET @Definition = REPLACE(
        @Definition,
        N'LEFT JOIN dbo.FMS_OtherBP_CLI bp ON bp.BP_Code = d.VendorCode
                LEFT JOIN dbo.FMS_ExpenseType expenseType ON expenseType.Expense_Code = d.ExpenseTypeCode',
        N'OUTER APPLY
                (
                    SELECT TOP (1) VendorName
                    FROM
                    (
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee_CCI
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee_AJVR
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee_ALC
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee_CMC
                        UNION ALL
                        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), CardCode) COLLATE DATABASE_DEFAULT)), N'''') AS VendorCode,
                               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), CardName) COLLATE DATABASE_DEFAULT)), N'''') AS VendorName
                        FROM FineReport..vwVendorPayee_CHI
                    ) vendorRows
                    WHERE vendorRows.VendorCode = d.VendorCode
                      AND vendorRows.VendorName IS NOT NULL
                    ORDER BY vendorRows.VendorName
                ) vendorInfo
                OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT)), N'''') AS ExpenseName
                    FROM dbo.vw_FMS_ExpenseType expenseTypeView
                    WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), expenseTypeView.Code) COLLATE DATABASE_DEFAULT)), N'''') = d.ExpenseTypeCode
                    ORDER BY LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT))
                ) expenseTypeInfo');

    SET @Changed = 1;
END;

IF @Definition LIKE N'%expenseType.Expense_Name%'
BEGIN
    SET @Definition = REPLACE(
        @Definition,
        N'COALESCE(NULLIF(LTRIM(RTRIM(expenseType.Expense_Name)), N''''), d.ExpenseTypeCode, N'''') AS expenseType,',
        N'COALESCE(expenseTypeInfo.ExpenseName, d.ExpenseTypeCode, N'''') AS expenseType,');

    SET @Changed = 1;
END;

IF @Definition LIKE N'%pettyExpenseType.Expense_Name%'
BEGIN
    SET @Definition = REPLACE(
        @Definition,
        N'COALESCE(NULLIF(LTRIM(RTRIM(pettyExpenseType.Expense_Name)), N''''), pc.NatureOfExpense, N'''') AS natureOfExpense,',
        N'COALESCE(pettyExpenseTypeInfo.ExpenseName, pc.NatureOfExpense, N'''') AS natureOfExpense,');

    SET @Definition = REPLACE(
        @Definition,
        N'LEFT JOIN dbo.FMS_ExpenseType pettyExpenseType ON pettyExpenseType.Expense_Code = pc.NatureOfExpense',
        N'OUTER APPLY
                (
                    SELECT TOP (1) NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT)), N'''') AS ExpenseName
                    FROM dbo.vw_FMS_ExpenseType expenseTypeView
                    WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), expenseTypeView.Code) COLLATE DATABASE_DEFAULT)), N'''') = pc.NatureOfExpense
                    ORDER BY LTRIM(RTRIM(CONVERT(nvarchar(200), expenseTypeView.[Name]) COLLATE DATABASE_DEFAULT))
                ) pettyExpenseTypeInfo');

    SET @Changed = 1;
END;

IF @Changed = 1
BEGIN
    IF @Definition NOT LIKE N'%vendorInfo.VendorName%'
       OR @Definition NOT LIKE N'%expenseTypeInfo.ExpenseName%'
    BEGIN
        THROW 51131, 'The receipt detail display-name block was not updated correctly.', 1;
    END;

    SET @ProcedureIndex = PATINDEX(N'%PROCEDURE%', @Definition);

    IF @ProcedureIndex <= 0
    BEGIN
        THROW 51132, 'Could not locate procedure keyword in sp_CashAdvanceRequests_GetForUser definition.', 1;
    END;

    SET @Definition = STUFF(@Definition, 1, @ProcedureIndex - 1, N'ALTER ');

    EXEC sys.sp_executesql @Definition;
END;
GO
