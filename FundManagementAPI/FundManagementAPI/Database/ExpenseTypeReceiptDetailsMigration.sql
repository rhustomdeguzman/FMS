USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ExpenseTypeCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ExpenseTypeCode varchar(50) NULL;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ExpenseType') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN ExpenseType nvarchar(200) NULL;
END;

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ExpenseTypes_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ObjectId int = OBJECT_ID(N'dbo.vw_FMS_ExpenseType', N'V');
    DECLARE @CodeColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @ObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @CodeColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Expense_Code', N'ExpenseCode', N'ExpenseTypeCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'Expense_Code' THEN 1
            WHEN N'ExpenseCode' THEN 2
            WHEN N'ExpenseTypeCode' THEN 3
            WHEN N'Code' THEN 4
            ELSE 5
        END;

        SELECT TOP (1) @NameColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Expense_Name', N'ExpenseName', N'ExpenseType', N'Name', N'Description')
        ORDER BY CASE [name]
            WHEN N'Expense_Name' THEN 1
            WHEN N'ExpenseName' THEN 2
            WHEN N'ExpenseType' THEN 3
            WHEN N'Name' THEN 4
            WHEN N'Description' THEN 5
            ELSE 6
        END;
    END;

    IF @CodeColumn IS NULL OR @NameColumn IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(50)) AS Expense_Code,
               CAST(N'' AS nvarchar(200)) AS Expense_Name
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH ExpenseTypes AS
    (
        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), ' + QUOTENAME(@CodeColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Expense_Code,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Expense_Name
        FROM dbo.vw_FMS_ExpenseType
    )
    SELECT Expense_Code,
           MIN(Expense_Name) AS Expense_Name
    FROM ExpenseTypes
    WHERE Expense_Code IS NOT NULL
      AND Expense_Name IS NOT NULL
    GROUP BY Expense_Code
    ORDER BY MIN(Expense_Name);';

    EXEC sys.sp_executesql @Sql;
END
GO
