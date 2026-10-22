SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Roles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.vw_FMS_AppUsers', N'V') IS NULL
BEGIN
    THROW 51091, 'Normalized app user tables must exist before enabling editable departments and titles.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_Update
    @AdminUserId int,
    @UserId int,
    @Username nvarchar(50),
    @DisplayName nvarchar(150),
    @Department nvarchar(100),
    @Role nvarchar(50),
    @Title nvarchar(100),
    @Password nvarchar(200) = NULL,
    @PettyCashFundAmount decimal(19,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Username = LOWER(LTRIM(RTRIM(@Username)));
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
    SELECT @RoleCode = RoleCode
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

    IF NULLIF(@Username, N'') IS NULL
       OR NULLIF(@DisplayName, N'') IS NULL
       OR NULLIF(@Department, N'') IS NULL
       OR NULLIF(@Title, N'') IS NULL
    BEGIN
        RAISERROR('Username, display name, department, and title are required.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE Username = @Username AND UserId <> @UserId)
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

    UPDATE dbo.FMS_AppUsers
    SET Username = @Username,
        DisplayName = @DisplayName,
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
