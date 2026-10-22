SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
BEGIN
    THROW 51050, 'FMS_AppUsers table was not found.', 1;
END
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
    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           userRow.Role
    FROM dbo.FMS_AppUsers userRow
    CROSS APPLY
    (
        SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(userRow.Role, N'-', N' '), N'_', N' ')))) AS RoleAlias
    ) normalized
    LEFT JOIN @RoleAliases roleAlias ON roleAlias.RoleAlias = normalized.RoleAlias
    WHERE roleAlias.RoleCode IS NULL;

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
