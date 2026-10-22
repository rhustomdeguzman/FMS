USE [FMS];
GO

CREATE OR ALTER PROCEDURE dbo.sp_Companies_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ObjectId int = OBJECT_ID(N'dbo.vw_FMS_Company', N'V');
    DECLARE @IdColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @ObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @IdColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'ID', N'Id', N'CompanyId', N'CompanyID', N'CompanyCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'ID' THEN 1
            WHEN N'Id' THEN 2
            WHEN N'CompanyId' THEN 3
            WHEN N'CompanyID' THEN 4
            WHEN N'CompanyCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END;

        SELECT TOP (1) @NameColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @ObjectId
          AND [name] IN (N'Name', N'CompanyName')
        ORDER BY CASE [name]
            WHEN N'Name' THEN 1
            WHEN N'CompanyName' THEN 2
            ELSE 3
        END;
    END;

    IF @NameColumn IS NULL
    BEGIN
        SELECT CAST(NULL AS int) AS CompanyId,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH Companies AS
    (
        SELECT ' + CASE
                WHEN @IdColumn IS NULL THEN N'CAST(NULL AS int)'
                ELSE N'TRY_CONVERT(int, ' + QUOTENAME(@IdColumn) + N')'
            END + N' AS CompanyId,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS [Name]
        FROM dbo.vw_FMS_Company
    )
    SELECT CompanyId,
           [Name]
    FROM Companies
    WHERE CompanyId IS NOT NULL
      AND [Name] IS NOT NULL
    GROUP BY CompanyId, [Name]
    ORDER BY CompanyId, [Name];';

    EXEC sys.sp_executesql @Sql;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CompanyReferences_GetByCompany
    @CompanyId int,
    @ReferenceKind nvarchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CompanyObjectId int = OBJECT_ID(N'dbo.vw_FMS_Company', N'V');
    DECLARE @IdColumn sysname = NULL;
    DECLARE @SourceColumn sysname = CASE @ReferenceKind
        WHEN N'vendor' THEN N'VendorPayee_Table'
        WHEN N'project' THEN N'Projects_Table'
        WHEN N'profit-center' THEN N'ProfitCenter_Table'
        ELSE NULL
    END;
    DECLARE @SourceTable nvarchar(512) = NULL;
    DECLARE @SourceObject sysname = NULL;
    DECLARE @ReferenceObjectId int = NULL;
    DECLARE @CodeColumn sysname = NULL;
    DECLARE @NameColumn sysname = NULL;

    IF @CompanyObjectId IS NOT NULL
    BEGIN
        SELECT TOP (1) @IdColumn = [name]
        FROM sys.columns
        WHERE [object_id] = @CompanyObjectId
          AND [name] IN (N'ID', N'Id', N'CompanyId', N'CompanyID', N'CompanyCode', N'Code')
        ORDER BY CASE [name]
            WHEN N'ID' THEN 1
            WHEN N'Id' THEN 2
            WHEN N'CompanyId' THEN 3
            WHEN N'CompanyID' THEN 4
            WHEN N'CompanyCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END;
    END;

    IF @CompanyObjectId IS NULL
       OR @IdColumn IS NULL
       OR @SourceColumn IS NULL
       OR NOT EXISTS
       (
           SELECT 1
           FROM sys.columns
           WHERE [object_id] = @CompanyObjectId
             AND [name] = @SourceColumn
       )
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @LookupSql nvarchar(max) = N'
    SELECT TOP (1) @SourceTable = NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(512), ' + QUOTENAME(@SourceColumn) + N') COLLATE DATABASE_DEFAULT)), N'''')
    FROM dbo.vw_FMS_Company
    WHERE TRY_CONVERT(int, ' + QUOTENAME(@IdColumn) + N') = @CompanyId;';

    EXEC sys.sp_executesql
        @LookupSql,
        N'@CompanyId int, @SourceTable nvarchar(512) OUTPUT',
        @CompanyId,
        @SourceTable OUTPUT;

    SET @SourceTable = NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(@SourceTable, N'[', N''), N']', N''))), N'');
    SET @SourceObject = PARSENAME(@SourceTable, 1);

    IF @SourceObject IS NULL AND LEN(@SourceTable) <= 128
    BEGIN
        SET @SourceObject = @SourceTable;
    END;

    IF @SourceObject IS NULL
       OR @SourceObject COLLATE Latin1_General_BIN2 LIKE N'%[^A-Za-z0-9_]%'
       OR OBJECT_ID(N'FineReport..' + QUOTENAME(@SourceObject)) IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    SET @ReferenceObjectId = OBJECT_ID(N'FineReport..' + QUOTENAME(@SourceObject));

    SELECT TOP (1) @CodeColumn = [name]
    FROM FineReport.sys.columns
    WHERE [object_id] = @ReferenceObjectId
      AND
      (
          (@ReferenceKind = N'vendor'
           AND [name] IN (N'BP_Code', N'BPCode', N'VendorPayee_Code', N'VendorPayeeCode', N'VendorCode', N'CardCode', N'Code'))
          OR (@ReferenceKind = N'project'
              AND [name] IN (N'ProjCode', N'ProjectCode', N'Code'))
          OR (@ReferenceKind = N'profit-center'
              AND [name] IN (N'OcrCode', N'PrcCode', N'ProfitCenterCode', N'CostCenterCode', N'CenterCode', N'Code'))
      )
    ORDER BY CASE
        WHEN @ReferenceKind = N'vendor' THEN CASE [name]
            WHEN N'BP_Code' THEN 1
            WHEN N'BPCode' THEN 2
            WHEN N'VendorPayee_Code' THEN 3
            WHEN N'VendorPayeeCode' THEN 4
            WHEN N'VendorCode' THEN 5
            WHEN N'CardCode' THEN 6
            WHEN N'Code' THEN 7
            ELSE 8
        END
        WHEN @ReferenceKind = N'project' THEN CASE [name]
            WHEN N'ProjCode' THEN 1
            WHEN N'ProjectCode' THEN 2
            WHEN N'Code' THEN 3
            ELSE 4
        END
        WHEN @ReferenceKind = N'profit-center' THEN CASE [name]
            WHEN N'OcrCode' THEN 1
            WHEN N'PrcCode' THEN 2
            WHEN N'ProfitCenterCode' THEN 3
            WHEN N'CostCenterCode' THEN 4
            WHEN N'CenterCode' THEN 5
            WHEN N'Code' THEN 6
            ELSE 7
        END
    END;

    SELECT TOP (1) @NameColumn = [name]
    FROM FineReport.sys.columns
    WHERE [object_id] = @ReferenceObjectId
      AND
      (
          (@ReferenceKind = N'vendor'
           AND [name] IN (N'BP_Name', N'BPName', N'VendorPayee_Name', N'VendorPayeeName', N'VendorName', N'CardName', N'Name'))
          OR (@ReferenceKind = N'project'
              AND [name] IN (N'ProjName', N'ProjectName', N'Name', N'Description'))
          OR (@ReferenceKind = N'profit-center'
              AND [name] IN (N'OcrName', N'PrcName', N'ProfitCenterName', N'CostCenterName', N'CenterName', N'Name', N'Description'))
      )
    ORDER BY CASE
        WHEN @ReferenceKind = N'vendor' THEN CASE [name]
            WHEN N'BP_Name' THEN 1
            WHEN N'BPName' THEN 2
            WHEN N'VendorPayee_Name' THEN 3
            WHEN N'VendorPayeeName' THEN 4
            WHEN N'VendorName' THEN 5
            WHEN N'CardName' THEN 6
            WHEN N'Name' THEN 7
            ELSE 8
        END
        WHEN @ReferenceKind = N'project' THEN CASE [name]
            WHEN N'ProjName' THEN 1
            WHEN N'ProjectName' THEN 2
            WHEN N'Name' THEN 3
            WHEN N'Description' THEN 4
            ELSE 5
        END
        WHEN @ReferenceKind = N'profit-center' THEN CASE [name]
            WHEN N'OcrName' THEN 1
            WHEN N'PrcName' THEN 2
            WHEN N'ProfitCenterName' THEN 3
            WHEN N'CostCenterName' THEN 4
            WHEN N'CenterName' THEN 5
            WHEN N'Name' THEN 6
            WHEN N'Description' THEN 7
            ELSE 8
        END
    END;

    IF @CodeColumn IS NULL AND @NameColumn IS NOT NULL
    BEGIN
        SET @CodeColumn = @NameColumn;
    END;

    IF @ReferenceKind = N'profit-center'
       AND @SourceObject COLLATE Latin1_General_CI_AS = N'vwProfitCenters'
       AND EXISTS
       (
           SELECT 1
           FROM FineReport.sys.columns
           WHERE [object_id] = @ReferenceObjectId
             AND [name] = N'OcrCode'
       )
    BEGIN
        SET @CodeColumn = N'OcrCode';
    END;

    IF @NameColumn IS NULL AND @CodeColumn IS NOT NULL
    BEGIN
        SET @NameColumn = @CodeColumn;
    END;

    IF @CodeColumn IS NULL OR @NameColumn IS NULL
    BEGIN
        SELECT CAST(N'' AS nvarchar(100)) AS Code,
               CAST(N'' AS nvarchar(200)) AS [Name]
        WHERE 1 = 0;
        RETURN;
    END;

    DECLARE @CodeFilter nvarchar(max) = N'';

    IF @ReferenceKind = N'profit-center'
       AND @SourceObject COLLATE Latin1_General_CI_AS = N'vwProfitCenters'
    BEGIN
        SET @CodeFilter = N'
      AND Code LIKE N''OD-DP%''';
    END;

    DECLARE @Sql nvarchar(max) = N'
    WITH ReferenceRows AS
    (
        SELECT NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), ' + QUOTENAME(@CodeColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS Code,
               NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(200), ' + QUOTENAME(@NameColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS [Name]
        FROM FineReport..' + QUOTENAME(@SourceObject) + N'
    )
    SELECT Code,
           MIN([Name]) AS [Name]
    FROM ReferenceRows
    WHERE Code IS NOT NULL
      AND [Name] IS NOT NULL' + @CodeFilter + N'
    GROUP BY Code
    ORDER BY MIN([Name]);';

    EXEC sys.sp_executesql @Sql;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_BusinessPartners_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'vendor';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Projects_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'project';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProfitCenters_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'profit-center';
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CostCenters_GetByCompany
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_CompanyReferences_GetByCompany
        @CompanyId = @CompanyId,
        @ReferenceKind = N'profit-center';
END
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
