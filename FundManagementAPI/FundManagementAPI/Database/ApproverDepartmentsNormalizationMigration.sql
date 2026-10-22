SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Roles', N'U') IS NULL
BEGIN
    THROW 51120, 'Required FMS user and department tables were not found.', 1;
END
GO

IF OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_ApproverDepartments
    (
        UserID int NOT NULL,
        DepartmentCode int NOT NULL,
        CONSTRAINT PK_ApproverDepartments PRIMARY KEY (UserID, DepartmentCode),
        CONSTRAINT FK_ApproverDepartments_AppUsers FOREIGN KEY (UserID)
            REFERENCES dbo.FMS_AppUsers(UserId) ON DELETE CASCADE,
        CONSTRAINT FK_ApproverDepartments_Departments FOREIGN KEY (DepartmentCode)
            REFERENCES dbo.FMS_Departments(DepartmentCode)
    );

    CREATE INDEX IX_ApproverDepartments_DepartmentCode
        ON dbo.FMS_ApproverDepartments(DepartmentCode, UserID);
END
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.FMS_AppUsers', N'DepartmentCode') IS NOT NULL
    BEGIN
        INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode)
        SELECT UserId, DepartmentCode
        FROM dbo.FMS_AppUsers
        WHERE DepartmentCode IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_ApproverDepartments existingAssignment
              WHERE existingAssignment.UserID = FMS_AppUsers.UserId
                AND existingAssignment.DepartmentCode = FMS_AppUsers.DepartmentCode
          );
    END;

    IF OBJECT_ID(N'FineReport..FineReport_RFP_Approvers', N'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode)
        SELECT DISTINCT appUser.UserId,
               TRY_CONVERT(int, fineReportApprover.ID)
        FROM FineReport..FineReport_RFP_Approvers fineReportApprover
        INNER JOIN dbo.FMS_AppUsers appUser
            ON appUser.Username = LTRIM(RTRIM(CONVERT(nvarchar(50), fineReportApprover.ApprvCode)))
        INNER JOIN dbo.FMS_Departments department
            ON department.DepartmentCode = TRY_CONVERT(int, fineReportApprover.ID)
        WHERE fineReportApprover.RoleCode = N'H'
          AND fineReportApprover.Active = N'1'
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_ApproverDepartments existingAssignment
              WHERE existingAssignment.UserID = appUser.UserId
                AND existingAssignment.DepartmentCode = TRY_CONVERT(int, fineReportApprover.ID)
          );
    END;

    IF OBJECT_ID(N'dbo.vw_FMS_AppUsers', N'V') IS NOT NULL
    BEGIN
        DROP VIEW dbo.vw_FMS_AppUsers;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
          AND name = N'IX_AppUsers_DepartmentCode'
    )
    BEGIN
        DROP INDEX IX_AppUsers_DepartmentCode ON dbo.FMS_AppUsers;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
          AND name = N'FK_AppUsers_DepartmentCode'
    )
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers DROP CONSTRAINT FK_AppUsers_DepartmentCode;
    END;

    IF COL_LENGTH(N'dbo.FMS_AppUsers', N'DepartmentCode') IS NOT NULL
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers DROP COLUMN DepartmentCode;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    ;THROW;
END CATCH
GO

CREATE OR ALTER VIEW dbo.vw_FMS_AppUsers
AS
    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           department.DepartmentName AS Department,
           roleRow.RoleKey AS Role,
           userRow.Title,
           userRow.PasswordHash,
           userRow.IsActive,
           userRow.AuditDate,
           userRow.UpdatedAt,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           primaryDepartment.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    OUTER APPLY
    (
        SELECT MAX(assignment.DepartmentCode) AS DepartmentCode
        FROM dbo.FMS_ApproverDepartments assignment
        WHERE assignment.UserID = userRow.UserId
    ) primaryDepartment
    LEFT JOIN dbo.FMS_Departments department
        ON department.DepartmentCode = primaryDepartment.DepartmentCode;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_Create
    @AdminUserId int,
    @Username nvarchar(50),
    @Password nvarchar(200),
    @DisplayName nvarchar(150),
    @Department nvarchar(200),
    @Role nvarchar(50),
    @Title nvarchar(100),
    @PettyCashFundAmount decimal(19,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LOWER(LTRIM(RTRIM(@Username)));
    SET @DisplayName = LTRIM(RTRIM(@DisplayName));
    SET @Department = LTRIM(RTRIM(@Department));

    DECLARE @RoleAlias nvarchar(100) = LOWER(LTRIM(RTRIM(REPLACE(REPLACE(@Role, N'-', N' '), N'_', N' '))));
    SET @Role = CASE
        WHEN @RoleAlias IN (N'admin', N'administrator', N'system admin', N'system administrator') THEN N'admin'
        WHEN @RoleAlias IN (N'requestor', N'requester', N'requestor user', N'requester user') THEN N'requestor'
        WHEN @RoleAlias IN (N'department head', N'department approver', N'dept head', N'depthead', N'approver') THEN N'department_head'
        WHEN @RoleAlias IN (N'accounting', N'accounting reviewer', N'accounts payable', N'account payable', N'ap') THEN N'accounting'
        WHEN @RoleAlias = N'cashier' THEN N'cashier'
        WHEN @RoleAlias IN (N'custodian', N'petty cash custodian') THEN N'custodian'
        ELSE @RoleAlias
    END;

    DECLARE @RoleCode int;
    SELECT @RoleCode = RoleCode, @Title = DefaultTitle
    FROM dbo.FMS_Roles
    WHERE RoleKey = @Role AND IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
        THROW 51121, 'Only an active admin user can manage users.', 1;
    IF @RoleCode IS NULL
        THROW 51122, 'Role is not valid.', 1;
    IF NULLIF(@Username, N'') IS NULL OR NULLIF(@Password, N'') IS NULL
       OR NULLIF(@DisplayName, N'') IS NULL OR NULLIF(@Department, N'') IS NULL
       OR NULLIF(@Title, N'') IS NULL
        THROW 51123, 'Username, password, display name, department, and title are required.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE Username = @Username)
        THROW 51124, 'Username already exists.', 1;
    IF @Role = N'custodian' AND COALESCE(@PettyCashFundAmount, 0) <= 0
        THROW 51125, 'Custodian initial fund must be greater than zero.', 1;

    DECLARE @DepartmentCode int;
    SELECT @DepartmentCode = MIN(DepartmentCode)
    FROM dbo.FMS_Departments WITH (UPDLOCK, HOLDLOCK)
    WHERE DepartmentName = @Department;

    IF @DepartmentCode IS NULL
    BEGIN
        INSERT INTO dbo.FMS_Departments (DepartmentName) VALUES (@Department);
        SET @DepartmentCode = CONVERT(int, SCOPE_IDENTITY());
    END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.FMS_AppUsers
        (Username, DisplayName, RoleCode, Title, PasswordHash, PettyCashFundAmount)
    VALUES
        (@Username, @DisplayName, @RoleCode, @Title,
         HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password)),
         CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END);

    DECLARE @NewUserId int = CONVERT(int, SCOPE_IDENTITY());
    INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode)
    VALUES (@NewUserId, @DepartmentCode);

    COMMIT TRANSACTION;

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive,
           PettyCashFundAmount, RoleCode, DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @NewUserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_Update
    @AdminUserId int,
    @UserId int,
    @DisplayName nvarchar(150),
    @Department nvarchar(200),
    @Role nvarchar(50),
    @Title nvarchar(100),
    @Password nvarchar(200) = NULL,
    @PettyCashFundAmount decimal(19,4) = NULL,
    @Username nvarchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LOWER(LTRIM(RTRIM(COALESCE(@Username, (SELECT Username FROM dbo.FMS_AppUsers WHERE UserId = @UserId)))));
    SET @DisplayName = LTRIM(RTRIM(@DisplayName));
    SET @Department = LTRIM(RTRIM(@Department));
    SET @Title = LTRIM(RTRIM(@Title));

    DECLARE @RoleAlias nvarchar(100) = LOWER(LTRIM(RTRIM(REPLACE(REPLACE(@Role, N'-', N' '), N'_', N' '))));
    SET @Role = CASE
        WHEN @RoleAlias IN (N'admin', N'administrator', N'system admin', N'system administrator') THEN N'admin'
        WHEN @RoleAlias IN (N'requestor', N'requester', N'requestor user', N'requester user') THEN N'requestor'
        WHEN @RoleAlias IN (N'department head', N'department approver', N'dept head', N'depthead', N'approver') THEN N'department_head'
        WHEN @RoleAlias IN (N'accounting', N'accounting reviewer', N'accounts payable', N'account payable', N'ap') THEN N'accounting'
        WHEN @RoleAlias = N'cashier' THEN N'cashier'
        WHEN @RoleAlias IN (N'custodian', N'petty cash custodian') THEN N'custodian'
        ELSE @RoleAlias
    END;

    DECLARE @RoleCode int;
    SELECT @RoleCode = RoleCode FROM dbo.FMS_Roles WHERE RoleKey = @Role AND IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
        THROW 51121, 'Only an active admin user can manage users.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @UserId)
        THROW 51126, 'User was not found.', 1;
    IF @UserId = @AdminUserId AND @RoleCode <> 1
        THROW 51127, 'An admin cannot remove their own admin role.', 1;
    IF @RoleCode IS NULL
        THROW 51122, 'Role is not valid.', 1;
    IF NULLIF(@Username, N'') IS NULL OR NULLIF(@DisplayName, N'') IS NULL
       OR NULLIF(@Department, N'') IS NULL OR NULLIF(@Title, N'') IS NULL
        THROW 51128, 'Username, display name, department, and title are required.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE Username = @Username AND UserId <> @UserId)
        THROW 51124, 'Username already exists.', 1;
    IF @Role = N'custodian' AND COALESCE(@PettyCashFundAmount, 0) <= 0
        THROW 51125, 'Custodian initial fund must be greater than zero.', 1;

    DECLARE @DepartmentCode int;
    SELECT @DepartmentCode = MIN(DepartmentCode)
    FROM dbo.FMS_Departments WITH (UPDLOCK, HOLDLOCK)
    WHERE DepartmentName = @Department;

    IF @DepartmentCode IS NULL
    BEGIN
        INSERT INTO dbo.FMS_Departments (DepartmentName) VALUES (@Department);
        SET @DepartmentCode = CONVERT(int, SCOPE_IDENTITY());
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.FMS_AppUsers
    SET Username = @Username,
        DisplayName = @DisplayName,
        RoleCode = @RoleCode,
        Title = @Title,
        PasswordHash = CASE WHEN NULLIF(@Password, N'') IS NULL THEN PasswordHash
                            ELSE HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password)) END,
        PettyCashFundAmount = CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END,
        IsActive = 1,
        UpdatedAt = GETDATE()
    WHERE UserId = @UserId;

    DELETE FROM dbo.FMS_ApproverDepartments WHERE UserID = @UserId;
    INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode)
    VALUES (@UserId, @DepartmentCode);

    COMMIT TRANSACTION;

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive,
           PettyCashFundAmount, RoleCode, DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @UserId;
END
GO
