SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH(N'dbo.FMS_AppUsers', N'PettyCashFundAmount') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_AppUsers ADD PettyCashFundAmount decimal(19,4) NULL;
END
GO

DECLARE @RoleAliases TABLE
(
    RoleAlias nvarchar(100) NOT NULL PRIMARY KEY,
    RoleCode nvarchar(50) NOT NULL
);

INSERT INTO @RoleAliases (RoleAlias, RoleCode)
VALUES
    (N'admin', N'admin'),
    (N'administrator', N'admin'),
    (N'system admin', N'admin'),
    (N'system administrator', N'admin'),
    (N'requestor', N'requestor'),
    (N'requester', N'requestor'),
    (N'requestor user', N'requestor'),
    (N'requester user', N'requestor'),
    (N'department head', N'department_head'),
    (N'department approver', N'department_head'),
    (N'dept head', N'department_head'),
    (N'depthead', N'department_head'),
    (N'approver', N'department_head'),
    (N'accounting', N'accounting'),
    (N'accounting reviewer', N'accounting'),
    (N'accounts payable', N'accounting'),
    (N'account payable', N'accounting'),
    (N'ap', N'accounting'),
    (N'cashier', N'cashier'),
    (N'custodian', N'custodian'),
    (N'petty cash custodian', N'custodian');

DECLARE @RoleTitles TABLE
(
    RoleCode nvarchar(50) NOT NULL PRIMARY KEY,
    Title nvarchar(100) NOT NULL
);

INSERT INTO @RoleTitles (RoleCode, Title)
VALUES
    (N'admin', N'Administrator'),
    (N'requestor', N'Requestor'),
    (N'department_head', N'Department Head'),
    (N'accounting', N'Accounting Reviewer'),
    (N'cashier', N'Cashier'),
    (N'custodian', N'Petty Cash Custodian');

IF EXISTS
(
    SELECT 1
    FROM dbo.FMS_AppUsers userRow
    CROSS APPLY
    (
        SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
    ) normalized
    LEFT JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
    WHERE roleAlias.RoleCode IS NULL
)
BEGIN
    THROW 51051, 'One or more FMS_AppUsers roles could not be normalized.', 1;
END

UPDATE userRow
SET Role = roleAlias.RoleCode,
    Title = roleTitle.Title,
    PettyCashFundAmount = CASE
        WHEN roleAlias.RoleCode = N'custodian' THEN COALESCE(NULLIF(userRow.PettyCashFundAmount, 0), 20000)
        ELSE NULL
    END
FROM dbo.FMS_AppUsers userRow
CROSS APPLY
(
    SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
) normalized
INNER JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
INNER JOIN @RoleTitles roleTitle ON roleTitle.RoleCode = roleAlias.RoleCode;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_AppUsers_Role')
BEGIN
    ALTER TABLE dbo.FMS_AppUsers DROP CONSTRAINT CK_AppUsers_Role;
END
GO

ALTER TABLE dbo.FMS_AppUsers
ADD CONSTRAINT CK_AppUsers_Role CHECK (Role IN ('admin', 'requestor', 'department_head', 'accounting', 'cashier', 'custodian'));
GO

IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE Username = N'admin')
BEGIN
    INSERT INTO dbo.FMS_AppUsers (Username, DisplayName, Department, Role, Title, PasswordHash)
    VALUES
        (N'admin', N'System Admin', N'Administration', N'admin', N'Administrator', HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123')));
END
ELSE
BEGIN
    UPDATE dbo.FMS_AppUsers
    SET Role = N'admin',
        DisplayName = COALESCE(NULLIF(DisplayName, N''), N'System Admin'),
        Department = COALESCE(NULLIF(Department, N''), N'Administration'),
        Title = COALESCE(NULLIF(Title, N''), N'Administrator'),
        IsActive = 1
    WHERE Username = N'admin';
END
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
           PettyCashFundAmount
    FROM dbo.FMS_AppUsers
    WHERE @IncludeInactive = 1 OR IsActive = 1
    ORDER BY Role, DisplayName;
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
           PettyCashFundAmount
    FROM dbo.FMS_AppUsers
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
    SET @Title = CASE @Role
        WHEN N'admin' THEN N'Administrator'
        WHEN N'requestor' THEN N'Requestor'
        WHEN N'department_head' THEN N'Department Head'
        WHEN N'accounting' THEN N'Accounting Reviewer'
        WHEN N'cashier' THEN N'Cashier'
        WHEN N'custodian' THEN N'Petty Cash Custodian'
        ELSE LTRIM(RTRIM(@Title))
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND Role = N'admin' AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can manage users.', 16, 1);
        RETURN;
    END

    IF @Role NOT IN (N'admin', N'requestor', N'department_head', N'accounting', N'cashier', N'custodian')
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

    INSERT INTO dbo.FMS_AppUsers
        (Username, DisplayName, Department, Role, Title, PasswordHash, PettyCashFundAmount)
    VALUES
        (
            @Username,
            @DisplayName,
            @Department,
            @Role,
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
           PettyCashFundAmount
    FROM dbo.FMS_AppUsers
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
    SET @Title = CASE @Role
        WHEN N'admin' THEN N'Administrator'
        WHEN N'requestor' THEN N'Requestor'
        WHEN N'department_head' THEN N'Department Head'
        WHEN N'accounting' THEN N'Accounting Reviewer'
        WHEN N'cashier' THEN N'Cashier'
        WHEN N'custodian' THEN N'Petty Cash Custodian'
        ELSE LTRIM(RTRIM(@Title))
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND Role = N'admin' AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can manage users.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @UserId)
    BEGIN
        RAISERROR('User was not found.', 16, 1);
        RETURN;
    END

    IF @UserId = @AdminUserId AND @Role <> N'admin'
    BEGIN
        RAISERROR('An admin cannot remove their own admin role.', 16, 1);
        RETURN;
    END

    IF @Role NOT IN (N'admin', N'requestor', N'department_head', N'accounting', N'cashier', N'custodian')
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

    UPDATE dbo.FMS_AppUsers
    SET DisplayName = @DisplayName,
        Department = @Department,
        Role = @Role,
        Title = @Title,
        PasswordHash = CASE
            WHEN NULLIF(@Password, N'') IS NULL THEN PasswordHash
            ELSE HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password))
        END,
        PettyCashFundAmount = CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END,
        IsActive = 1
    WHERE UserId = @UserId;

    SELECT UserId,
           Username,
           DisplayName,
           Department,
           Role,
           Title,
           IsActive,
           PettyCashFundAmount
    FROM dbo.FMS_AppUsers
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

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND Role = N'admin' AND IsActive = 1)
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
    SET PettyCashFundAmount = @PettyCashFundAmount
    WHERE UserId = @UserId
      AND Role = N'custodian'
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
           PettyCashFundAmount
    FROM dbo.FMS_AppUsers
    WHERE UserId = @UserId;
END
GO
