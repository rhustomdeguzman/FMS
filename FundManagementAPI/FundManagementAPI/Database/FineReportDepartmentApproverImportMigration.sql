SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Roles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.vw_FMS_AppUsers', N'V') IS NULL
BEGIN
    THROW 51110, 'Normalized app user tables must exist before importing FineReport department approvers.', 1;
END
GO

IF COL_LENGTH(N'dbo.FMS_AppUsers', N'Role') IS NOT NULL
   OR COL_LENGTH(N'dbo.FMS_AppUsers', N'Department') IS NOT NULL
BEGIN
    THROW 51111, 'DropAppUsersRoleDepartmentTextColumnsMigration.sql must be executed before importing FineReport department approvers.', 1;
END
GO

IF OBJECT_ID(N'FineReport..FineReport_RFP_Approvers', N'U') IS NULL
BEGIN
    THROW 51112, 'FineReport..FineReport_RFP_Approvers table was not found.', 1;
END
GO

IF COL_LENGTH(N'dbo.FMS_Departments', N'DepartmentGroup') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_Departments ADD DepartmentGroup nvarchar(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_Departments', N'DepartmentName') < 400
BEGIN
    ALTER TABLE dbo.FMS_Departments ALTER COLUMN DepartmentName nvarchar(200) NOT NULL;
END
GO

IF EXISTS
(
    SELECT 1
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FMS_Departments')
      AND name = N'UX_Departments_DepartmentName'
)
BEGIN
    ALTER TABLE dbo.FMS_Departments DROP CONSTRAINT UX_Departments_DepartmentName;
END
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @IdentityInsertDepartments bit = 0;
    DECLARE @DefaultPassword nvarchar(200) = N'password123';

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_Roles WHERE RoleCode = 3 AND RoleKey = N'department_head' AND IsActive = 1)
    BEGIN
        THROW 51118, 'Active department approver role was not found in FMS_Roles.', 1;
    END

    CREATE TABLE #FineReportApproversRaw
    (
        DepartmentCode int NULL,
        DepartmentName nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        DepartmentGroup nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        Email nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        IdentityKey nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        Username nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        DisplayName nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
        Title nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #FineReportApproversRaw
        (DepartmentCode, DepartmentName, DepartmentGroup, Email, IdentityKey, Username, DisplayName, Title)
    SELECT TRY_CONVERT(int, fineReportApprover.[ID]),
           NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[Name]))), N''),
           NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[DeptGroup]))), N''),
           LOWER(NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[Email]))), N'')),
           COALESCE(
               LOWER(NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[Email]))), N'')),
               CONCAT(N'username:', LOWER(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[ApprvCode])))))
           ),
           NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[ApprvCode]))), N''),
           NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(TRY_CONVERT(nvarchar(4000), fineReportApprover.[DisplayName]), CHAR(13), N''), CHAR(10), N''))), N''),
           NULLIF(LTRIM(RTRIM(TRY_CONVERT(nvarchar(4000), fineReportApprover.[Alias]))), N'')
    FROM FineReport..FineReport_RFP_Approvers fineReportApprover
    WHERE fineReportApprover.[RoleCode] = N'H'
      AND fineReportApprover.[Active] = N'1';

    IF EXISTS
    (
        SELECT 1
        FROM #FineReportApproversRaw
        WHERE DepartmentCode IS NULL
           OR DepartmentName IS NULL
           OR Username IS NULL
           OR DisplayName IS NULL
           OR Title IS NULL
    )
    BEGIN
        THROW 51113, 'FineReport department approvers include rows with missing ID, Name, ApprvCode, DisplayName, or Alias values.', 1;
    END

    IF EXISTS
    (
        SELECT 1
        FROM #FineReportApproversRaw
        WHERE LEN(DepartmentName) > 200
           OR LEN(COALESCE(DepartmentGroup, N'')) > 100
           OR LEN(Username) > 50
           OR LEN(COALESCE(Email, N'')) > 320
           OR LEN(DisplayName) > 200
           OR LEN(Title) > 100
    )
    BEGIN
        THROW 51114, 'FineReport department approver values exceed the target FMS column lengths.', 1;
    END

    IF EXISTS
    (
        SELECT 1
        FROM #FineReportApproversRaw
        GROUP BY DepartmentCode
        HAVING COUNT(DISTINCT DepartmentName) > 1
            OR COUNT(DISTINCT COALESCE(DepartmentGroup, N'')) > 1
    )
    BEGIN
        THROW 51115, 'FineReport returned conflicting department names or groups for the same ID.', 1;
    END

    CREATE TABLE #FineReportDepartments
    (
        DepartmentCode int NOT NULL PRIMARY KEY,
        DepartmentName nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
        DepartmentGroup nvarchar(100) COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #FineReportDepartments (DepartmentCode, DepartmentName, DepartmentGroup)
    SELECT DepartmentCode,
           MAX(CONVERT(nvarchar(200), DepartmentName)),
           NULLIF(MAX(CONVERT(nvarchar(100), COALESCE(DepartmentGroup, N''))), N'')
    FROM #FineReportApproversRaw
    GROUP BY DepartmentCode;

    CREATE TABLE #FineReportApprovers
    (
        IdentityKey nvarchar(400) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
        Email nvarchar(320) COLLATE DATABASE_DEFAULT NULL,
        Username nvarchar(50) COLLATE DATABASE_DEFAULT NOT NULL,
        DisplayName nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
        Title nvarchar(100) COLLATE DATABASE_DEFAULT NOT NULL,
        DepartmentCode int NOT NULL
    );

    ;WITH RankedApprovers AS
    (
        SELECT IdentityKey,
               Email,
               Username,
               DisplayName,
               Title,
               DepartmentCode,
               ROW_NUMBER() OVER (PARTITION BY IdentityKey ORDER BY DepartmentCode DESC, Username) AS RowNumber
        FROM #FineReportApproversRaw
    )
    INSERT INTO #FineReportApprovers (IdentityKey, Email, Username, DisplayName, Title, DepartmentCode)
    SELECT CONVERT(nvarchar(400), IdentityKey),
           CONVERT(nvarchar(320), Email),
           CONVERT(nvarchar(50), COALESCE(Email, Username)),
           CONVERT(nvarchar(200), DisplayName),
           CONVERT(nvarchar(100), Title),
           DepartmentCode
    FROM RankedApprovers
    WHERE RowNumber = 1;

    UPDATE targetDepartment
    SET DepartmentName = sourceDepartment.DepartmentName,
        DepartmentGroup = sourceDepartment.DepartmentGroup,
        IsActive = 1,
        UpdatedAt = GETDATE()
    FROM dbo.FMS_Departments targetDepartment
    INNER JOIN #FineReportDepartments sourceDepartment
        ON sourceDepartment.DepartmentCode = targetDepartment.DepartmentCode;

    IF EXISTS
    (
        SELECT 1
        FROM #FineReportDepartments sourceDepartment
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_Departments existingDepartment
            WHERE existingDepartment.DepartmentCode = sourceDepartment.DepartmentCode
        )
    )
    BEGIN
        SET IDENTITY_INSERT dbo.FMS_Departments ON;
        SET @IdentityInsertDepartments = 1;

        INSERT INTO dbo.FMS_Departments (DepartmentCode, DepartmentName, DepartmentGroup, IsActive)
        SELECT sourceDepartment.DepartmentCode,
               sourceDepartment.DepartmentName,
               sourceDepartment.DepartmentGroup,
               1
        FROM #FineReportDepartments sourceDepartment
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_Departments existingDepartment
            WHERE existingDepartment.DepartmentCode = sourceDepartment.DepartmentCode
        );

        SET IDENTITY_INSERT dbo.FMS_Departments OFF;
        SET @IdentityInsertDepartments = 0;
    END

    UPDATE targetUser
    SET Username = sourceApprover.Username,
        DisplayName = sourceApprover.DisplayName,
        Email = sourceApprover.Email,
        RoleCode = 3,
        Title = sourceApprover.Title,
        PettyCashFundAmount = NULL,
        IsActive = 1,
        UpdatedAt = GETDATE()
    FROM dbo.FMS_AppUsers targetUser
    INNER JOIN #FineReportApprovers sourceApprover
        ON (sourceApprover.Email IS NOT NULL AND sourceApprover.Email = targetUser.Email)
        OR (sourceApprover.Email IS NULL AND sourceApprover.Username = targetUser.Username);

    INSERT INTO dbo.FMS_AppUsers
        (Username, DisplayName, Email, RoleCode, Title, PasswordHash, PettyCashFundAmount)
    SELECT sourceApprover.Username,
           sourceApprover.DisplayName,
           sourceApprover.Email,
           3,
           sourceApprover.Title,
           HASHBYTES('SHA2_256', CONVERT(varbinary(max), @DefaultPassword)),
           NULL
    FROM #FineReportApprovers sourceApprover
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.FMS_AppUsers existingUser
        WHERE (sourceApprover.Email IS NOT NULL AND existingUser.Email = sourceApprover.Email)
           OR (sourceApprover.Email IS NULL AND existingUser.Username = sourceApprover.Username)
    );

    INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode, DepartmentGroup)
    SELECT DISTINCT targetUser.UserId,
           sourceApprover.DepartmentCode,
           TRY_CONVERT(int, sourceApprover.DepartmentGroup)
    FROM #FineReportApproversRaw sourceApprover
    INNER JOIN dbo.FMS_AppUsers targetUser
        ON (sourceApprover.Email IS NOT NULL AND targetUser.Email = sourceApprover.Email)
        OR (sourceApprover.Email IS NULL AND targetUser.Username = sourceApprover.Username)
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.FMS_ApproverDepartments existingAssignment
        WHERE existingAssignment.UserID = targetUser.UserId
          AND existingAssignment.DepartmentCode = sourceApprover.DepartmentCode
    );

    UPDATE assignment
    SET DepartmentGroup = TRY_CONVERT(int, sourceApprover.DepartmentGroup)
    FROM dbo.FMS_ApproverDepartments assignment
    INNER JOIN dbo.FMS_AppUsers targetUser ON targetUser.UserId = assignment.UserID
    INNER JOIN #FineReportApproversRaw sourceApprover
        ON sourceApprover.DepartmentCode = assignment.DepartmentCode
       AND
       (
           (sourceApprover.Email IS NOT NULL AND targetUser.Email = sourceApprover.Email)
           OR (sourceApprover.Email IS NULL AND targetUser.Username = sourceApprover.Username)
       );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    IF @IdentityInsertDepartments = 1
    BEGIN
        SET IDENTITY_INSERT dbo.FMS_Departments OFF;
    END

    ;THROW;
END CATCH
GO
