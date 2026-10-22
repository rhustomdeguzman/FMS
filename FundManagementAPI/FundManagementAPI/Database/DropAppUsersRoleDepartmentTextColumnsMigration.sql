SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
BEGIN
    THROW 51070, 'FMS_AppUsers table was not found.', 1;
END
GO

IF OBJECT_ID(N'dbo.FMS_Roles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
   OR COL_LENGTH(N'dbo.FMS_AppUsers', N'RoleCode') IS NULL
   OR COL_LENGTH(N'dbo.FMS_AppUsers', N'DepartmentCode') IS NULL
BEGIN
    THROW 51071, 'Role/department lookup migration must be executed before dropping text columns.', 1;
END
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
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    INNER JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_GetAll
    @IncludeInactive bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount,
           RoleCode,
           DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE @IncludeInactive = 1 OR IsActive = 1
    ORDER BY RoleCode, Department, DisplayName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Auth_Login
    @Username nvarchar(50),
    @Password nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PasswordHash varbinary(32) = HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password));

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount,
           RoleCode,
           DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE Username = @Username
      AND PasswordHash = @PasswordHash
      AND IsActive = 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_Create
    @AdminUserId int,
    @Username nvarchar(50),
    @Password nvarchar(200),
    @DisplayName nvarchar(150),
    @Department nvarchar(100),
    @Role nvarchar(50),
    @Title nvarchar(100),
    @PettyCashFundAmount decimal(19,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
    SELECT @RoleCode = RoleCode,
           @Title = DefaultTitle
    FROM dbo.FMS_Roles
    WHERE RoleKey = @Role
      AND IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can manage users.', 16, 1);
        RETURN;
    END

    IF @RoleCode IS NULL
    BEGIN
        RAISERROR('Role is not valid.', 16, 1);
        RETURN;
    END

    IF NULLIF(@Username, N'') IS NULL
       OR NULLIF(@Password, N'') IS NULL
       OR NULLIF(@DisplayName, N'') IS NULL
       OR NULLIF(@Department, N'') IS NULL
       OR NULLIF(@Title, N'') IS NULL
    BEGIN
        RAISERROR('Username, password, display name, department, and title are required.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE Username = @Username)
    BEGIN
        RAISERROR('Username already exists.', 16, 1);
        RETURN;
    END

    IF @Role = N'custodian' AND COALESCE(@PettyCashFundAmount, 0) <= 0
    BEGIN
        RAISERROR('Custodian initial fund must be greater than zero.', 16, 1);
        RETURN;
    END

    DECLARE @DepartmentCode int;

    SELECT @DepartmentCode = DepartmentCode
    FROM dbo.FMS_Departments WITH (UPDLOCK, HOLDLOCK)
    WHERE DepartmentName = @Department;

    IF @DepartmentCode IS NULL
    BEGIN
        INSERT INTO dbo.FMS_Departments (DepartmentName)
        VALUES (@Department);

        SET @DepartmentCode = CONVERT(int, SCOPE_IDENTITY());
    END

    INSERT INTO dbo.FMS_AppUsers
        (Username, DisplayName, DepartmentCode, RoleCode, Title, PasswordHash, PettyCashFundAmount)
    VALUES
        (
            @Username,
            @DisplayName,
            @DepartmentCode,
            @RoleCode,
            @Title,
            HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password)),
            CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END
        );

    DECLARE @NewUserId int = CONVERT(int, SCOPE_IDENTITY());

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount,
           RoleCode,
           DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @NewUserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_Update
    @AdminUserId int,
    @UserId int,
    @DisplayName nvarchar(150),
    @Department nvarchar(100),
    @Role nvarchar(50),
    @Title nvarchar(100),
    @Password nvarchar(200) = NULL,
    @PettyCashFundAmount decimal(19,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
    SELECT @RoleCode = RoleCode,
           @Title = DefaultTitle
    FROM dbo.FMS_Roles
    WHERE RoleKey = @Role
      AND IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can manage users.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @UserId)
    BEGIN
        RAISERROR('User was not found.', 16, 1);
        RETURN;
    END

    IF @UserId = @AdminUserId AND @RoleCode <> 1
    BEGIN
        RAISERROR('An admin cannot remove their own admin role.', 16, 1);
        RETURN;
    END

    IF @RoleCode IS NULL
    BEGIN
        RAISERROR('Role is not valid.', 16, 1);
        RETURN;
    END

    IF NULLIF(@DisplayName, N'') IS NULL
       OR NULLIF(@Department, N'') IS NULL
       OR NULLIF(@Title, N'') IS NULL
    BEGIN
        RAISERROR('Display name, department, and title are required.', 16, 1);
        RETURN;
    END

    IF @Role = N'custodian' AND COALESCE(@PettyCashFundAmount, 0) <= 0
    BEGIN
        RAISERROR('Custodian initial fund must be greater than zero.', 16, 1);
        RETURN;
    END

    DECLARE @DepartmentCode int;

    SELECT @DepartmentCode = DepartmentCode
    FROM dbo.FMS_Departments WITH (UPDLOCK, HOLDLOCK)
    WHERE DepartmentName = @Department;

    IF @DepartmentCode IS NULL
    BEGIN
        INSERT INTO dbo.FMS_Departments (DepartmentName)
        VALUES (@Department);

        SET @DepartmentCode = CONVERT(int, SCOPE_IDENTITY());
    END

    UPDATE dbo.FMS_AppUsers
    SET DisplayName = @DisplayName,
        DepartmentCode = @DepartmentCode,
        RoleCode = @RoleCode,
        Title = @Title,
        PasswordHash = CASE
            WHEN NULLIF(@Password, N'') IS NULL THEN PasswordHash
            ELSE HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password))
        END,
        PettyCashFundAmount = CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END,
        IsActive = 1,
        UpdatedAt = GETDATE()
    WHERE UserId = @UserId;

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount,
           RoleCode,
           DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_UpdateCustodianFund
    @AdminUserId int,
    @UserId int,
    @PettyCashFundAmount decimal(19,4)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can manage custodian funds.', 16, 1);
        RETURN;
    END

    IF @PettyCashFundAmount <= 0
    BEGIN
        RAISERROR('Custodian initial fund must be greater than zero.', 16, 1);
        RETURN;
    END

    UPDATE dbo.FMS_AppUsers
    SET PettyCashFundAmount = @PettyCashFundAmount,
        UpdatedAt = GETDATE()
    WHERE UserId = @UserId
      AND RoleCode = 6
      AND IsActive = 1;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Custodian user was not found.', 16, 1);
        RETURN;
    END

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount,
           RoleCode,
           DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @UserId;
END
GO

DECLARE @ProcedureName sysname;
DECLARE @Definition nvarchar(max);
DECLARE @CreateIndex int;

DECLARE procedureCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT ProcedureName
FROM
(
    VALUES
        (N'sp_CashAdvanceRequests_GetForUser'),
        (N'sp_CashAdvanceRequests_Transfer'),
        (N'sp_CashAdvanceRequests_TransferResponse'),
        (N'sp_PettyCashRequests_Create'),
        (N'sp_PettyCashRequests_CreateReplenishment'),
        (N'sp_PettyCashRequests_CustodianDecision'),
        (N'sp_PettyCashRequests_SubmitReplenishmentCv')
) source(ProcedureName);

OPEN procedureCursor;
FETCH NEXT FROM procedureCursor INTO @ProcedureName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @Definition = OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@ProcedureName)));

    IF @Definition IS NOT NULL
    BEGIN
        SET @Definition = REPLACE(@Definition, N'dbo.FMS_AppUsers', N'dbo.vw_FMS_AppUsers');
        SET @CreateIndex = PATINDEX(N'%CREATE%PROCEDURE%', @Definition);

        IF @CreateIndex > 0
        BEGIN
            SET @Definition = STUFF(@Definition, @CreateIndex, LEN(N'CREATE'), N'ALTER ');
        END

        EXEC sys.sp_executesql @Definition;
    END

    FETCH NEXT FROM procedureCursor INTO @ProcedureName;
END

CLOSE procedureCursor;
DEALLOCATE procedureCursor;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_AppUsers_Role')
BEGIN
    ALTER TABLE dbo.FMS_AppUsers DROP CONSTRAINT CK_AppUsers_Role;
END
GO

IF COL_LENGTH(N'dbo.FMS_AppUsers', N'Role') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_AppUsers DROP COLUMN Role;
END
GO

IF COL_LENGTH(N'dbo.FMS_AppUsers', N'Department') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_AppUsers DROP COLUMN Department;
END
GO
