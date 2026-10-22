USE FundManagementSystem;
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
BEGIN
    THROW 50001, 'FMS_AppUsers table was not found. Run the API Database/FundManagementSystem.sql script first.', 1;
END
GO

DECLARE @SeedAppUsers TABLE
(
    Username nvarchar(50) NOT NULL PRIMARY KEY,
    DisplayName nvarchar(200) NOT NULL,
    Department nvarchar(100) NOT NULL,
    Role nvarchar(50) NOT NULL,
    Title nvarchar(100) NOT NULL,
    PlainPassword nvarchar(200) NOT NULL,
    PettyCashFundAmount decimal(19,4) NULL
);

INSERT INTO @SeedAppUsers (Username, DisplayName, Department, Role, Title, PlainPassword, PettyCashFundAmount)
VALUES
    (N'requestor', N'Ruru Pogi', N'MIS', N'requestor', N'Requestor', N'password123', NULL),
    (N'depthead', N'Migs Llanera', N'MIS', N'department_head', N'Department Head', N'password123', NULL),
    (N'accounting', N'Joselle De Guzman', N'Accounting', N'accounting', N'Accounting Reviewer', N'password123', NULL),
    (N'cashier', N'Anna Vea', N'Accounting', N'cashier', N'Cashier', N'password123', NULL),
    (N'it.requestor', N'Rovin Baqurin', N'IT & Systems', N'requestor', N'Requestor', N'password123', NULL),
    (N'hr.requestor', N'Hannah Reyes', N'HR', N'requestor', N'Requestor', N'password123', NULL),
    (N'hr.head', N'Hector Dela Cruz', N'HR', N'department_head', N'Department Head', N'password123', NULL),
    (N'its.head', N'Iris Sy', N'IT & Systems', N'department_head', N'Department Head', N'password123', NULL),
    (N'eng.requestor', N'Erika Santos', N'Engineering', N'requestor', N'Requestor', N'password123', NULL),
    (N'eng.head', N'Enrico Cruz', N'Engineering', N'department_head', N'Department Head', N'password123', NULL),
    (N'acct.requestor', N'Aileen Mendoza', N'Accounting', N'requestor', N'Requestor', N'password123', NULL),
    (N'acct.head', N'Anton Reyes', N'Accounting', N'department_head', N'Department Head', N'password123', NULL),
    (N'am.requestor', N'Cara Villanueva', N'Accounts Management', N'requestor', N'Requestor', N'password123', NULL),
    (N'am.head', N'Carlo Navarro', N'Accounts Management', N'department_head', N'Department Head', N'password123', NULL),
    (N'custodian', N'Petty Cash Custodian', N'Accounting', N'custodian', N'Petty Cash Custodian', N'password123', 20000),
    (N'mis.custodian', N'MIS Petty Cash Custodian', N'MIS', N'custodian', N'Petty Cash Custodian', N'password123', 20000),
    (N'its.custodian', N'IT & Systems Petty Cash Custodian', N'IT & Systems', N'custodian', N'Petty Cash Custodian', N'password123', 20000),
    (N'hr.custodian', N'HR Petty Cash Custodian', N'HR', N'custodian', N'Petty Cash Custodian', N'password123', 20000),
    (N'eng.custodian', N'Engineering Petty Cash Custodian', N'Engineering', N'custodian', N'Petty Cash Custodian', N'password123', 20000),
    (N'am.custodian', N'Accounts Management Petty Cash Custodian', N'Accounts Management', N'custodian', N'Petty Cash Custodian', N'password123', 20000);

UPDATE target
SET DisplayName = source.DisplayName,
    Department = source.Department,
    Role = source.Role,
    Title = source.Title,
    PettyCashFundAmount = CASE WHEN source.Role = N'custodian' THEN COALESCE(source.PettyCashFundAmount, 20000) ELSE NULL END,
    PasswordHash = HASHBYTES('SHA2_256', CONVERT(varbinary(max), source.PlainPassword)),
    IsActive = 1,
    UpdatedAt = GETDATE()
FROM dbo.FMS_AppUsers target
INNER JOIN @SeedAppUsers source ON source.Username = target.Username;

INSERT INTO dbo.FMS_AppUsers (Username, DisplayName, Department, Role, Title, PasswordHash, PettyCashFundAmount)
SELECT source.Username,
       source.DisplayName,
       source.Department,
       source.Role,
       source.Title,
       HASHBYTES('SHA2_256', CONVERT(varbinary(max), source.PlainPassword)),
       CASE WHEN source.Role = N'custodian' THEN COALESCE(source.PettyCashFundAmount, 20000) ELSE NULL END
FROM @SeedAppUsers source
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FMS_AppUsers existing
    WHERE existing.Username = source.Username
);
GO

IF OBJECT_ID(N'dbo.FMS_CashAdvanceRequests', N'U') IS NULL
BEGIN
    THROW 50002, 'FMS_CashAdvanceRequests table was not found. Run the API Database/FundManagementSystem.sql script first.', 1;
END
GO

DECLARE @SeedCashAdvanceRequests TABLE
(
    RequestNumber nvarchar(50) NOT NULL PRIMARY KEY,
    RequestorUsername nvarchar(50) NOT NULL,
    Amount decimal(19,4) NOT NULL,
    AmountSpent decimal(19,4) NULL,
    ReturnAmount decimal(19,4) NULL,
    ExcessAmount decimal(19,4) NULL,
    Purpose nvarchar(500) NOT NULL,
    Status nvarchar(50) NOT NULL,
    LiquidationNotes nvarchar(1000) NULL,
    DueDate date NULL
);

INSERT INTO @SeedCashAdvanceRequests
    (RequestNumber, RequestorUsername, Amount, AmountSpent, ReturnAmount, ExcessAmount, Purpose, Status, LiquidationNotes, DueDate)
VALUES
    (N'CA-2026-001', N'requestor', 5000, NULL, NULL, NULL, N'Business travel for client meeting', N'pending_liquidation', NULL, '2026-06-25'),
    (N'CA-2026-002', N'requestor', 3500, 3500, NULL, NULL, N'Office supplies purchase', N'pending_department_approval', N'Exact spend with receipts attached.', '2026-06-20'),
    (N'CA-2026-003', N'requestor', 8000, 6500, 1500, NULL, N'Conference registration and accommodation', N'pending_cashier_return', N'Conference cost was lower than planned.', '2026-06-30'),
    (N'CA-2026-004', N'it.requestor', 12000, 12000, NULL, NULL, N'Emergency equipment replacement', N'pending_accounting_review', N'Exact amount spent.', '2026-07-05'),
    (N'CA-2026-005', N'requestor', 2500, 3100, NULL, 600, N'Team meal for project deployment', N'pending_rfp_department_approval', N'Meal cost exceeded the approved cash advance.', '2026-06-22'),
    (N'CA-2026-101', N'hr.requestor', 4200, 4200, NULL, NULL, N'HR onboarding materials', N'pending_department_approval', N'New hire materials purchased.', '2026-07-10'),
    (N'CA-2026-201', N'it.requestor', 6800, 6800, NULL, NULL, N'Systems maintenance tools', N'pending_department_approval', N'Maintenance tools with invoice attached.', '2026-07-12'),
    (N'CA-2026-301', N'eng.requestor', 15000, NULL, NULL, NULL, N'Prototype field testing supplies', N'pending_liquidation', NULL, '2026-07-18'),
    (N'CA-2026-401', N'acct.requestor', 5400, 5100, 300, NULL, N'Audit working meal and transport', N'pending_department_approval', N'Return expected after department approval.', '2026-07-08'),
    (N'CA-2026-501', N'am.requestor', 9200, 9800, NULL, 600, N'Client presentation expenses', N'pending_department_approval', N'Client materials exceeded original estimate.', '2026-07-14');

INSERT INTO dbo.FMS_CashAdvanceRequests
    (RequestNumber, RequestorUserId, Department, Amount, AmountSpent, ReturnAmount, ExcessAmount, Purpose, Status, LiquidationNotes, DueDate)
SELECT source.RequestNumber,
       requestor.UserId,
       requestor.Department,
       source.Amount,
       source.AmountSpent,
       source.ReturnAmount,
       source.ExcessAmount,
       source.Purpose,
       source.Status,
       source.LiquidationNotes,
       source.DueDate
FROM @SeedCashAdvanceRequests source
INNER JOIN dbo.FMS_AppUsers requestor ON requestor.Username = source.RequestorUsername
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FMS_CashAdvanceRequests existing
    WHERE existing.RequestNumber = source.RequestNumber
);
GO
