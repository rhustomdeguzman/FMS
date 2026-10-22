SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.vw_FMS_AppUsers', N'V') IS NULL
BEGIN
    THROW 51080, 'Normalized app user role/department tables must exist before assigning department custodians.', 1;
END
GO

IF COL_LENGTH(N'dbo.FMS_Departments', N'CustodianUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_Departments ADD CustodianUserId int NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Departments_CustodianUserId')
BEGIN
    ALTER TABLE dbo.FMS_Departments WITH CHECK
    ADD CONSTRAINT FK_Departments_CustodianUserId
    FOREIGN KEY (CustodianUserId) REFERENCES dbo.FMS_AppUsers(UserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Departments_CustodianUserId' AND object_id = OBJECT_ID(N'dbo.FMS_Departments'))
BEGIN
    CREATE INDEX IX_Departments_CustodianUserId ON dbo.FMS_Departments(CustodianUserId);
END
GO

;WITH SameDepartmentCustodian AS
(
    SELECT department.DepartmentCode,
           MIN(custodian.UserId) AS CustodianUserId
    FROM dbo.FMS_Departments department
    INNER JOIN dbo.vw_FMS_AppUsers custodian ON custodian.DepartmentCode = department.DepartmentCode
    WHERE custodian.Role = N'custodian'
      AND custodian.IsActive = 1
    GROUP BY department.DepartmentCode
)
UPDATE department
SET CustodianUserId = sameDepartmentCustodian.CustodianUserId,
    UpdatedAt = GETDATE()
FROM dbo.FMS_Departments department
INNER JOIN SameDepartmentCustodian sameDepartmentCustodian
    ON sameDepartmentCustodian.DepartmentCode = department.DepartmentCode
WHERE department.CustodianUserId IS NULL;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DepartmentCustodians_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT department.DepartmentCode,
           department.DepartmentName,
           custodian.UserId AS CustodianUserId,
           custodian.DisplayName AS CustodianName,
           custodian.Department AS CustodianDepartment,
           custodian.PettyCashFundAmount AS CustodianFundAmount
    FROM dbo.FMS_Departments department
    LEFT JOIN dbo.vw_FMS_AppUsers custodian
        ON custodian.UserId = department.CustodianUserId
       AND custodian.Role = N'custodian'
       AND custodian.IsActive = 1
    WHERE department.IsActive = 1
    ORDER BY department.DepartmentName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_DepartmentCustodians_Assign
    @AdminUserId int,
    @DepartmentCode int,
    @CustodianUserId int
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @AdminUserId AND RoleCode = 1 AND IsActive = 1)
    BEGIN
        RAISERROR('Only an active admin user can assign department custodians.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_Departments WHERE DepartmentCode = @DepartmentCode AND IsActive = 1)
    BEGIN
        RAISERROR('Department was not found.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.FMS_AppUsers WHERE UserId = @CustodianUserId AND RoleCode = 6 AND IsActive = 1)
    BEGIN
        RAISERROR('A valid active custodian is required.', 16, 1);
        RETURN;
    END

    UPDATE dbo.FMS_Departments
    SET CustodianUserId = @CustodianUserId,
        UpdatedAt = GETDATE()
    WHERE DepartmentCode = @DepartmentCode;

    SELECT department.DepartmentCode,
           department.DepartmentName,
           custodian.UserId AS CustodianUserId,
           custodian.DisplayName AS CustodianName,
           custodian.Department AS CustodianDepartment,
           custodian.PettyCashFundAmount AS CustodianFundAmount
    FROM dbo.FMS_Departments department
    INNER JOIN dbo.vw_FMS_AppUsers custodian
        ON custodian.UserId = department.CustodianUserId
       AND custodian.Role = N'custodian'
       AND custodian.IsActive = 1
    WHERE department.DepartmentCode = @DepartmentCode;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_PettyCashRequests_Create
    @RequestType nvarchar(50),
    @RequestorUserId int,
    @CustodianUserId int,
    @Amount decimal(19,4),
    @Purpose nvarchar(500),
    @ReceiptDetailsJson nvarchar(max) = NULL,
    @TransportationDetailsJson nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RequestTypeNormalized nvarchar(50) = LOWER(LTRIM(RTRIM(@RequestType)));
    DECLARE @Department nvarchar(100);
    DECLARE @DepartmentCode int;
    DECLARE @AssignedCustodianUserId int;
    DECLARE @CustodianFundAmount decimal(19,4);
    DECLARE @AvailableAmount decimal(19,4);
    DECLARE @UsedAmount decimal(19,4);
    DECLARE @ReplenishmentAmount decimal(19,4);
    DECLARE @ReceiptTotal decimal(19,4);
    DECLARE @TransportationTotal decimal(19,4);
    DECLARE @RequestTotal decimal(19,4);
    DECLARE @RequestNumber nvarchar(50);

    CREATE TABLE #ReceiptRows
    (
        OrNumber nvarchar(100) NULL,
        Company nvarchar(200) NULL,
        Tin nvarchar(100) NULL,
        Address nvarchar(500) NULL,
        NatureOfExpense nvarchar(300) NULL,
        CostCenter nvarchar(100) NULL,
        TaxType nvarchar(20) NULL,
        Amount decimal(19,4) NULL,
        OrDate date NULL
    );

    CREATE TABLE #TransportationRows
    (
        [Description] nvarchar(300) NULL,
        FromLocation nvarchar(200) NULL,
        ToLocation nvarchar(200) NULL,
        TransactionDate date NULL,
        Amount decimal(19,4) NULL
    );

    IF @RequestTypeNormalized NOT IN (N'petty_cash', N'petty_cash_advance')
    BEGIN
        RAISERROR('Request type must be Petty Cash or Petty Cash Advance.', 16, 1);
        RETURN;
    END

    IF @Amount <= 0 OR @Amount > 5000
    BEGIN
        RAISERROR('Petty cash amount must be greater than zero and must not exceed PHP 5,000.', 16, 1);
        RETURN;
    END

    IF @RequestTypeNormalized = N'petty_cash'
    BEGIN
        IF ISJSON(@ReceiptDetailsJson) <> 1
        BEGIN
            RAISERROR('Receipt details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #ReceiptRows
            (OrNumber, Company, Tin, Address, NatureOfExpense, CostCenter, TaxType, Amount, OrDate)
        SELECT LTRIM(RTRIM(COALESCE(OrNumberCamel, OrNumberPascal))),
               LTRIM(RTRIM(COALESCE(CompanyCamel, CompanyPascal))),
               LTRIM(RTRIM(COALESCE(TinCamel, TinPascal))),
               LTRIM(RTRIM(COALESCE(AddressCamel, AddressPascal))),
               LTRIM(RTRIM(COALESCE(NatureOfExpenseCodeCamel, NatureOfExpenseCodePascal, NatureOfExpenseCamel, NatureOfExpensePascal))),
               LTRIM(RTRIM(COALESCE(CostCenterCodeCamel, CostCenterCodePascal, CostCenterCamel, CostCenterPascal))),
               LTRIM(RTRIM(COALESCE(TaxTypeCamel, TaxTypePascal))),
               COALESCE(AmountCamel, AmountPascal),
               COALESCE(OrDateCamel, OrDatePascal)
        FROM OPENJSON(@ReceiptDetailsJson)
        WITH
        (
            OrNumberCamel nvarchar(100) '$.orNumber',
            OrNumberPascal nvarchar(100) '$.OrNumber',
            CompanyCamel nvarchar(200) '$.company',
            CompanyPascal nvarchar(200) '$.Company',
            TinCamel nvarchar(100) '$.tin',
            TinPascal nvarchar(100) '$.Tin',
            AddressCamel nvarchar(500) '$.address',
            AddressPascal nvarchar(500) '$.Address',
            NatureOfExpenseCodeCamel nvarchar(300) '$.natureOfExpenseCode',
            NatureOfExpenseCodePascal nvarchar(300) '$.NatureOfExpenseCode',
            NatureOfExpenseCamel nvarchar(300) '$.natureOfExpense',
            NatureOfExpensePascal nvarchar(300) '$.NatureOfExpense',
            CostCenterCodeCamel nvarchar(100) '$.costCenterCode',
            CostCenterCodePascal nvarchar(100) '$.CostCenterCode',
            CostCenterCamel nvarchar(100) '$.costCenter',
            CostCenterPascal nvarchar(100) '$.CostCenter',
            TaxTypeCamel nvarchar(20) '$.taxType',
            TaxTypePascal nvarchar(20) '$.TaxType',
            AmountCamel decimal(19,4) '$.amount',
            AmountPascal decimal(19,4) '$.Amount',
            OrDateCamel date '$.orDate',
            OrDatePascal date '$.OrDate'
        );

        IF ISJSON(@TransportationDetailsJson) <> 1
        BEGIN
            RAISERROR('Transportation details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #TransportationRows
            ([Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT LTRIM(RTRIM(COALESCE(DescriptionCamel, DescriptionPascal))),
               LTRIM(RTRIM(COALESCE(FromCamel, FromPascal))),
               LTRIM(RTRIM(COALESCE(ToCamel, ToPascal))),
               COALESCE(TransactionDateCamel, TransactionDatePascal),
               COALESCE(AmountCamel, AmountPascal)
        FROM OPENJSON(@TransportationDetailsJson)
        WITH
        (
            DescriptionCamel nvarchar(300) '$.description',
            DescriptionPascal nvarchar(300) '$.Description',
            FromCamel nvarchar(200) '$.from',
            FromPascal nvarchar(200) '$.From',
            ToCamel nvarchar(200) '$.to',
            ToPascal nvarchar(200) '$.To',
            TransactionDateCamel date '$.transactionDate',
            TransactionDatePascal date '$.TransactionDate',
            AmountCamel decimal(19,4) '$.amount',
            AmountPascal decimal(19,4) '$.Amount'
        );

        IF NOT EXISTS (SELECT 1 FROM #ReceiptRows)
           AND NOT EXISTS (SELECT 1 FROM #TransportationRows)
        BEGIN
            RAISERROR('At least one receipt or transportation row is required for petty cash reimbursement.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #ReceiptRows
            WHERE NULLIF(OrNumber, N'') IS NULL
               OR NULLIF(Company, N'') IS NULL
               OR NULLIF(Tin, N'') IS NULL
               OR NULLIF(Address, N'') IS NULL
               OR NULLIF(NatureOfExpense, N'') IS NULL
               OR NULLIF(CostCenter, N'') IS NULL
               OR Amount IS NULL
               OR Amount <= 0
               OR OrDate IS NULL
        )
        BEGIN
            RAISERROR('Complete every receipt row before submitting petty cash reimbursement.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #TransportationRows
            WHERE NULLIF([Description], N'') IS NULL
               OR NULLIF(FromLocation, N'') IS NULL
               OR NULLIF(ToLocation, N'') IS NULL
               OR TransactionDate IS NULL
               OR Amount IS NULL
               OR Amount <= 0
        )
        BEGIN
            RAISERROR('Complete every transportation row before submitting petty cash reimbursement.', 16, 1);
            RETURN;
        END

        SELECT @ReceiptTotal = COALESCE(SUM(Amount), 0)
        FROM #ReceiptRows;

        SELECT @TransportationTotal = COALESCE(SUM(Amount), 0)
        FROM #TransportationRows;

        SET @RequestTotal = COALESCE(@ReceiptTotal, 0) + COALESCE(@TransportationTotal, 0);

        IF @RequestTotal + 0.01 < @Amount
        BEGIN
            RAISERROR('Petty cash actual spent must be equal to or greater than the reimbursement amount.', 16, 1);
            RETURN;
        END

        IF @RequestTotal - @Amount > 5000
        BEGIN
            RAISERROR('The reimbursement excess must not exceed the petty cash request cap.', 16, 1);
            RETURN;
        END
    END

    SELECT @Department = Department,
           @DepartmentCode = DepartmentCode
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @RequestorUserId
      AND Role = N'requestor'
      AND IsActive = 1;

    SELECT @AssignedCustodianUserId = CustodianUserId
    FROM dbo.FMS_Departments
    WHERE DepartmentCode = @DepartmentCode
      AND IsActive = 1;

    SELECT @CustodianFundAmount = COALESCE(PettyCashFundAmount, 20000)
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @CustodianUserId
      AND Role = N'custodian'
      AND IsActive = 1;

    IF @Department IS NULL OR @CustodianFundAmount IS NULL
    BEGIN
        RAISERROR('A valid requestor and custodian are required.', 16, 1);
        RETURN;
    END

    IF @AssignedCustodianUserId IS NULL
    BEGIN
        RAISERROR('No custodian is assigned to the requestor department.', 16, 1);
        RETURN;
    END

    IF @AssignedCustodianUserId <> @CustodianUserId
    BEGIN
        RAISERROR('Petty cash requests must use the custodian assigned to the requestor department.', 16, 1);
        RETURN;
    END

    SELECT @UsedAmount = COALESCE(SUM(
        CASE
            WHEN StatusId = 11 THEN 0
            WHEN RequestType = N'petty_cash' AND StatusId <> 8 THEN 0
            WHEN StatusId = 8 THEN COALESCE(AmountSpent, Amount - COALESCE(ReturnAmount, 0), Amount)
            ELSE Amount
        END
    ), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType IN (N'petty_cash', N'petty_cash_advance');

    SELECT @ReplenishmentAmount = COALESCE(SUM(Amount), 0)
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CustodianUserId = @CustodianUserId
      AND RequestType = N'petty_cash_replenishment'
      AND StatusId = 15;

    SET @AvailableAmount = @CustodianFundAmount - (@UsedAmount - @ReplenishmentAmount);

    IF @Amount > @AvailableAmount
    BEGIN
        RAISERROR('Petty cash amount exceeds the custodian available fund.', 16, 1);
        RETURN;
    END

    SET @RequestNumber = CONCAT(N'PC-', YEAR(GETDATE()), N'-', RIGHT(CONCAT(N'000', (
        SELECT COUNT(1) + 1
        FROM dbo.FMS_CashAdvanceRequests
        WHERE RequestType IN (N'petty_cash', N'petty_cash_advance')
          AND YEAR(AuditDate) = YEAR(GETDATE())
    )), 3));

    WHILE EXISTS (SELECT 1 FROM dbo.FMS_CashAdvanceRequests WHERE RequestNumber = @RequestNumber)
    BEGIN
        SET @RequestNumber = CONCAT(@RequestNumber, N'-', ABS(CHECKSUM(NEWID())) % 1000);
    END

    INSERT INTO dbo.FMS_CashAdvanceRequests
        (RequestNumber, RequestType, RequestorUserId, CurrentOwnerUserId, CustodianUserId, Department, Amount, RemainingAmount, Purpose, StatusId, DueDate)
    VALUES
        (@RequestNumber, @RequestTypeNormalized, @RequestorUserId, @RequestorUserId, @CustodianUserId, @Department, @Amount, @Amount, @Purpose, 1, DATEADD(DAY, 7, CONVERT(date, GETDATE())));

    DECLARE @CashAdvanceRequestId int = CONVERT(int, SCOPE_IDENTITY());

    IF @RequestTypeNormalized = N'petty_cash'
    BEGIN
        INSERT INTO dbo.FMS_PettyCashReceiptDetails
            (CashAdvanceRequestId, OrNumber, Company, Tin, Address, NatureOfExpense, CostCenter, TaxType, Amount, OrDate)
        SELECT @CashAdvanceRequestId,
               OrNumber,
               Company,
               Tin,
               Address,
               NatureOfExpense,
               CostCenter,
               TaxType,
               Amount,
               OrDate
        FROM #ReceiptRows;

        INSERT INTO dbo.FMS_PettyCashTransportationDetails
            (CashAdvanceRequestId, [Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT @CashAdvanceRequestId,
               [Description],
               FromLocation,
               ToLocation,
               TransactionDate,
               Amount
        FROM #TransportationRows;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'petty_cash_requested', @RequestorUserId, @Amount, 'Petty cash request submitted for department approval.');

    SELECT @CashAdvanceRequestId AS CashAdvanceRequestId;
END
GO
