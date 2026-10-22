SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
BEGIN
    THROW 51060, 'FMS_AppUsers table was not found.', 1;
END
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.FMS_Roles', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.FMS_Roles
        (
            RoleCode int NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
            RoleKey nvarchar(50) NOT NULL,
            RoleName nvarchar(100) NOT NULL,
            DefaultTitle nvarchar(100) NOT NULL,
            IsActive bit NOT NULL CONSTRAINT DF_Roles_IsActive DEFAULT (1),
            CONSTRAINT UX_Roles_RoleKey UNIQUE (RoleKey)
        );
    END

    MERGE dbo.FMS_Roles AS target
    USING
    (
        VALUES
            (1, N'admin', N'Admin', N'Administrator'),
            (2, N'requestor', N'Requestor', N'Requestor'),
            (3, N'department_head', N'Department Head', N'Department Head'),
            (4, N'accounting', N'Accounting', N'Accounting Reviewer'),
            (5, N'cashier', N'Cashier', N'Cashier'),
            (6, N'custodian', N'Custodian', N'Petty Cash Custodian')
    ) AS source(RoleCode, RoleKey, RoleName, DefaultTitle)
    ON target.RoleCode = source.RoleCode
    WHEN MATCHED THEN
        UPDATE SET RoleKey = source.RoleKey,
                   RoleName = source.RoleName,
                   DefaultTitle = source.DefaultTitle,
                   IsActive = 1
    WHEN NOT MATCHED THEN
        INSERT (RoleCode, RoleKey, RoleName, DefaultTitle)
        VALUES (source.RoleCode, source.RoleKey, source.RoleName, source.DefaultTitle);

    IF COL_LENGTH(N'dbo.FMS_Roles', N'SortOrder') IS NOT NULL
    BEGIN
        ALTER TABLE dbo.FMS_Roles DROP COLUMN SortOrder;
    END

    IF OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.FMS_Departments
        (
            DepartmentCode int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Departments PRIMARY KEY,
            DepartmentName nvarchar(200) NOT NULL,
            DepartmentGroup nvarchar(100) NULL,
            IsActive bit NOT NULL CONSTRAINT DF_Departments_IsActive DEFAULT (1),
            AuditDate datetime NOT NULL CONSTRAINT DF_Departments_AuditDate DEFAULT (GETDATE()),
            UpdatedAt datetime NULL
        );
    END

    IF COL_LENGTH(N'dbo.FMS_AppUsers', N'RoleCode') IS NULL
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers ADD RoleCode int NULL;
    END

    IF COL_LENGTH(N'dbo.FMS_AppUsers', N'DepartmentCode') IS NULL
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers ADD DepartmentCode int NULL;
    END

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @RoleAliases TABLE
    (
        RoleAlias nvarchar(100) NOT NULL PRIMARY KEY,
        RoleCode int NOT NULL
    );

    INSERT INTO @RoleAliases (RoleAlias, RoleCode)
    VALUES
        (N'admin', 1),
        (N'administrator', 1),
        (N'system admin', 1),
        (N'system administrator', 1),
        (N'requestor', 2),
        (N'requester', 2),
        (N'requestor user', 2),
        (N'requester user', 2),
        (N'department head', 3),
        (N'department approver', 3),
        (N'dept head', 3),
        (N'depthead', 3),
        (N'approver', 3),
        (N'accounting', 4),
        (N'accounting reviewer', 4),
        (N'accounts payable', 4),
        (N'account payable', 4),
        (N'ap', 4),
        (N'cashier', 5),
        (N'custodian', 6),
        (N'petty cash custodian', 6);

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
        THROW 51061, 'One or more FMS_AppUsers roles could not be normalized to a numeric RoleCode.', 1;
    END

    UPDATE userRow
    SET RoleCode = roleRow.RoleCode,
        Role = roleRow.RoleKey,
        Title = roleRow.DefaultTitle,
        PettyCashFundAmount = CASE
            WHEN roleRow.RoleKey = N'custodian' THEN COALESCE(NULLIF(userRow.PettyCashFundAmount, 0), 20000)
            ELSE NULL
        END
    FROM dbo.FMS_AppUsers userRow
    CROSS APPLY
    (
        SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
    ) normalized
    INNER JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = roleAlias.RoleCode;

    UPDATE dbo.FMS_AppUsers
    SET Department = LTRIM(RTRIM(Department))
    WHERE Department <> LTRIM(RTRIM(Department));

    INSERT INTO dbo.FMS_Departments (DepartmentName)
    SELECT DISTINCT userRow.Department
    FROM dbo.FMS_AppUsers userRow
    WHERE NULLIF(userRow.Department, N'') IS NOT NULL
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.FMS_Departments department
          WHERE department.DepartmentName = userRow.Department
      );

    UPDATE userRow
    SET DepartmentCode = department.DepartmentCode,
        Department = department.DepartmentName
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Departments department ON department.DepartmentName = userRow.Department;

    IF EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE RoleCode IS NULL OR DepartmentCode IS NULL)
    BEGIN
        THROW 51062, 'One or more FMS_AppUsers rows could not be assigned RoleCode or DepartmentCode.', 1;
    END

    IF EXISTS
    (
        SELECT 1
        FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
          AND name = N'RoleCode'
          AND is_nullable = 1
    )
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers ALTER COLUMN RoleCode int NOT NULL;
    END

    IF EXISTS
    (
        SELECT 1
        FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
          AND name = N'DepartmentCode'
          AND is_nullable = 1
    )
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers ALTER COLUMN DepartmentCode int NOT NULL;
    END

    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_AppUsers_Role')
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers DROP CONSTRAINT CK_AppUsers_Role;
    END

    ALTER TABLE dbo.FMS_AppUsers
    ADD CONSTRAINT CK_AppUsers_Role CHECK (Role IN ('admin', 'requestor', 'department_head', 'accounting', 'cashier', 'custodian'));

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_AppUsers_RoleCode')
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers WITH CHECK
        ADD CONSTRAINT FK_AppUsers_RoleCode
        FOREIGN KEY (RoleCode) REFERENCES dbo.FMS_Roles(RoleCode);
    END

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_AppUsers_DepartmentCode')
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers WITH CHECK
        ADD CONSTRAINT FK_AppUsers_DepartmentCode
        FOREIGN KEY (DepartmentCode) REFERENCES dbo.FMS_Departments(DepartmentCode);
    END

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AppUsers_RoleCode' AND object_id = OBJECT_ID(N'dbo.FMS_AppUsers'))
    BEGIN
        CREATE INDEX IX_AppUsers_RoleCode ON dbo.FMS_AppUsers(RoleCode);
    END

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AppUsers_DepartmentCode' AND object_id = OBJECT_ID(N'dbo.FMS_AppUsers'))
    BEGIN
        CREATE INDEX IX_AppUsers_DepartmentCode ON dbo.FMS_AppUsers(DepartmentCode);
    END

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_GetAll
    @IncludeInactive bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           COALESCE(department.DepartmentName, userRow.Department) AS Department,
           COALESCE(roleRow.RoleKey, userRow.Role) AS Role,
           userRow.Title,
           userRow.IsActive,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    LEFT JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    LEFT JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode
    WHERE @IncludeInactive = 1 OR userRow.IsActive = 1
    ORDER BY COALESCE(roleRow.RoleCode, userRow.RoleCode, 999), COALESCE(department.DepartmentName, userRow.Department), userRow.DisplayName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Auth_Login
    @Username nvarchar(50),
    @Password nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PasswordHash varbinary(32) = HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password));

    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           COALESCE(department.DepartmentName, userRow.Department) AS Department,
           COALESCE(roleRow.RoleKey, userRow.Role) AS Role,
           userRow.Title,
           userRow.IsActive,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    LEFT JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    LEFT JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode
    WHERE userRow.Username = @Username
      AND userRow.PasswordHash = @PasswordHash
      AND userRow.IsActive = 1;
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
        (Username, DisplayName, Department, DepartmentCode, Role, RoleCode, Title, PasswordHash, PettyCashFundAmount)
    VALUES
        (
            @Username,
            @DisplayName,
            @Department,
            @DepartmentCode,
            @Role,
            @RoleCode,
            @Title,
            HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password)),
            CASE WHEN @Role = N'custodian' THEN @PettyCashFundAmount ELSE NULL END
        );

    DECLARE @NewUserId int = CONVERT(int, SCOPE_IDENTITY());

    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           department.DepartmentName AS Department,
           roleRow.RoleKey AS Role,
           userRow.Title,
           userRow.IsActive,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    INNER JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode
    WHERE userRow.UserId = @NewUserId;
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
        Department = @Department,
        DepartmentCode = @DepartmentCode,
        Role = @Role,
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

    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           department.DepartmentName AS Department,
           roleRow.RoleKey AS Role,
           userRow.Title,
           userRow.IsActive,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    INNER JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode
    WHERE userRow.UserId = @UserId;
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

    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           department.DepartmentName AS Department,
           roleRow.RoleKey AS Role,
           userRow.Title,
           userRow.IsActive,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           userRow.DepartmentCode
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    INNER JOIN dbo.FMS_Departments department ON department.DepartmentCode = userRow.DepartmentCode
    WHERE userRow.UserId = @UserId;
END
GO
