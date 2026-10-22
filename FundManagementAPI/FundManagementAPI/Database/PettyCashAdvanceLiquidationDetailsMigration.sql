SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_SubmitLiquidation
    @CashAdvanceRequestId int,
    @LiquidatingUserId int = NULL,
    @AmountSpent decimal(19,4),
    @Notes nvarchar(max) = NULL,
    @AttachmentsJson nvarchar(max) = NULL,
    @ReceiptDetailsJson nvarchar(max) = NULL,
    @PettyCashReceiptDetailsJson nvarchar(max) = NULL,
    @PettyCashTransportationDetailsJson nvarchar(max) = NULL,
    @ReplaceExistingAttachments bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentOwnerUserId int;
    DECLARE @ActorUserId int;
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @RequestDepartment nvarchar(100);
    DECLARE @RequestType nvarchar(50);
    DECLARE @CustodianUserId int;
    DECLARE @LiquidatingUserRoleCode int;
    DECLARE @ShouldClaimFullCustody bit = 0;
    DECLARE @UsesPettyCashDetails bit = 0;
    DECLARE @ReceiptDetailTotal decimal(19,4) = 0;
    DECLARE @PettyCashReceiptTotal decimal(19,4) = 0;
    DECLARE @PettyCashTransportationTotal decimal(19,4) = 0;
    DECLARE @PettyCashDetailTotal decimal(19,4) = 0;

    CREATE TABLE #ReceiptRows
    (
        VendorCode varchar(50) NULL,
        [Description] nvarchar(500) NULL,
        ProjectCode nvarchar(20) NULL,
        ProfitCenterCode nvarchar(8) NULL,
        Amount decimal(19,4) NULL,
        InvoiceRef nvarchar(100) NULL,
        ExpenseTypeCode varchar(50) NULL
    );

    CREATE TABLE #PettyCashReceiptRows
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

    CREATE TABLE #PettyCashTransportationRows
    (
        [Description] nvarchar(300) NULL,
        FromLocation nvarchar(200) NULL,
        ToLocation nvarchar(200) NULL,
        TransactionDate date NULL,
        Amount decimal(19,4) NULL
    );

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @LiquidationBaseAmount = COALESCE(RemainingAmount, Amount),
           @RequestDepartment = Department,
           @RequestType = RequestType,
           @CustodianUserId = CustodianUserId
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    SELECT @LiquidatingUserRoleCode = RoleCode
    FROM dbo.FMS_AppUsers
    WHERE UserId = @LiquidatingUserId
      AND IsActive = 1;

    SET @ActorUserId = COALESCE(@LiquidatingUserId, @CurrentOwnerUserId);

    IF @LiquidatingUserId IS NOT NULL AND @LiquidatingUserId <> @CurrentOwnerUserId
    BEGIN
        IF @LiquidatingUserRoleCode = 3
           AND COALESCE(@RequestType, N'cash_advance') = N'cash_advance'
           AND EXISTS
           (
               SELECT 1
               FROM dbo.FMS_ApproverDepartments assignment
               INNER JOIN dbo.FMS_Departments department
                   ON department.DepartmentCode = assignment.DepartmentCode
               WHERE assignment.UserID = @LiquidatingUserId
                 AND LOWER(LTRIM(RTRIM(department.DepartmentName))) = LOWER(LTRIM(RTRIM(COALESCE(@RequestDepartment, N''))))
           )
        BEGIN
            SET @ShouldClaimFullCustody = 1;
        END
        ELSE
        BEGIN
            RAISERROR('Only the current owner or department approver can submit liquidation.', 16, 1);
            RETURN;
        END
    END

    SET @UsesPettyCashDetails = CASE
        WHEN @RequestType IN (N'petty_cash', N'petty_cash_advance') AND @CustodianUserId IS NOT NULL THEN 1
        ELSE 0
    END;

    IF @UsesPettyCashDetails = 1 AND @AmountSpent > @LiquidationBaseAmount
    BEGIN
        RAISERROR('Petty cash liquidation cannot exceed the released amount.', 16, 1);
        RETURN;
    END

    IF @UsesPettyCashDetails = 1
    BEGIN
        IF ISJSON(COALESCE(@PettyCashReceiptDetailsJson, N'[]')) <> 1
        BEGIN
            RAISERROR('Petty cash receipt details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #PettyCashReceiptRows
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
        FROM OPENJSON(COALESCE(@PettyCashReceiptDetailsJson, N'[]'))
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

        IF ISJSON(COALESCE(@PettyCashTransportationDetailsJson, N'[]')) <> 1
        BEGIN
            RAISERROR('Petty cash transportation details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #PettyCashTransportationRows
            ([Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT LTRIM(RTRIM(COALESCE(DescriptionCamel, DescriptionPascal))),
               LTRIM(RTRIM(COALESCE(FromCamel, FromPascal))),
               LTRIM(RTRIM(COALESCE(ToCamel, ToPascal))),
               COALESCE(TransactionDateCamel, TransactionDatePascal),
               COALESCE(AmountCamel, AmountPascal)
        FROM OPENJSON(COALESCE(@PettyCashTransportationDetailsJson, N'[]'))
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

        IF NOT EXISTS (SELECT 1 FROM #PettyCashReceiptRows)
           AND NOT EXISTS (SELECT 1 FROM #PettyCashTransportationRows)
        BEGIN
            RAISERROR('At least one receipt or transportation row is required for petty cash liquidation.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #PettyCashReceiptRows
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
            RAISERROR('Complete every petty cash receipt row before submitting liquidation.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #PettyCashTransportationRows
            WHERE NULLIF([Description], N'') IS NULL
               OR NULLIF(FromLocation, N'') IS NULL
               OR NULLIF(ToLocation, N'') IS NULL
               OR TransactionDate IS NULL
               OR Amount IS NULL
               OR Amount <= 0
        )
        BEGIN
            RAISERROR('Complete every transportation row before submitting liquidation.', 16, 1);
            RETURN;
        END

        SELECT @PettyCashReceiptTotal = COALESCE(SUM(Amount), 0)
        FROM #PettyCashReceiptRows;

        SELECT @PettyCashTransportationTotal = COALESCE(SUM(Amount), 0)
        FROM #PettyCashTransportationRows;

        SET @PettyCashDetailTotal = COALESCE(@PettyCashReceiptTotal, 0) + COALESCE(@PettyCashTransportationTotal, 0);

        IF ABS(@PettyCashDetailTotal - @AmountSpent) > 0.01
        BEGIN
            RAISERROR('Petty cash liquidation amount must match the receipt and transportation total.', 16, 1);
            RETURN;
        END
    END
    ELSE
    BEGIN
        IF ISJSON(COALESCE(@ReceiptDetailsJson, N'[]')) <> 1
        BEGIN
            RAISERROR('Receipt details are invalid.', 16, 1);
            RETURN;
        END

        INSERT INTO #ReceiptRows
            (VendorCode, [Description], ProjectCode, ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode)
        SELECT LTRIM(RTRIM(COALESCE(VendorCodeCamel, VendorCodePascal))),
               LTRIM(RTRIM(COALESCE(DescriptionCamel, DescriptionPascal))),
               LTRIM(RTRIM(COALESCE(ProjectCodeCamel, ProjectCodePascal))),
               LTRIM(RTRIM(COALESCE(ProfitCenterCodeCamel, ProfitCenterCodePascal))),
               COALESCE(AmountCamel, AmountPascal),
               LTRIM(RTRIM(COALESCE(InvoiceRefCamel, InvoiceRefPascal))),
               LTRIM(RTRIM(COALESCE(ExpenseTypeCodeCamel, ExpenseTypeCodePascal)))
        FROM OPENJSON(COALESCE(@ReceiptDetailsJson, N'[]'))
        WITH
        (
            VendorCodeCamel varchar(50) '$.vendorCode',
            VendorCodePascal varchar(50) '$.VendorCode',
            DescriptionCamel nvarchar(500) '$.description',
            DescriptionPascal nvarchar(500) '$.Description',
            ProjectCodeCamel nvarchar(20) '$.projectCode',
            ProjectCodePascal nvarchar(20) '$.ProjectCode',
            ProfitCenterCodeCamel nvarchar(8) '$.profitCenterCode',
            ProfitCenterCodePascal nvarchar(8) '$.ProfitCenterCode',
            AmountCamel decimal(19,4) '$.amount',
            AmountPascal decimal(19,4) '$.Amount',
            InvoiceRefCamel nvarchar(100) '$.invoiceRef',
            InvoiceRefPascal nvarchar(100) '$.InvoiceRef',
            ExpenseTypeCodeCamel varchar(50) '$.expenseTypeCode',
            ExpenseTypeCodePascal varchar(50) '$.ExpenseTypeCode'
        );

        IF NOT EXISTS (SELECT 1 FROM #ReceiptRows)
        BEGIN
            RAISERROR('At least one receipt detail row is required for liquidation.', 16, 1);
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM #ReceiptRows
            WHERE NULLIF(VendorCode, '') IS NULL
               OR NULLIF([Description], N'') IS NULL
               OR NULLIF(ProjectCode, N'') IS NULL
               OR NULLIF(ProfitCenterCode, N'') IS NULL
               OR Amount IS NULL
               OR Amount <= 0
               OR NULLIF(InvoiceRef, N'') IS NULL
               OR NULLIF(ExpenseTypeCode, '') IS NULL
        )
        BEGIN
            RAISERROR('Complete every receipt detail row before submitting liquidation.', 16, 1);
            RETURN;
        END

        SELECT @ReceiptDetailTotal = COALESCE(SUM(Amount), 0)
        FROM #ReceiptRows;

        IF ABS(@ReceiptDetailTotal - @AmountSpent) > 0.01
        BEGIN
            RAISERROR('Liquidation amount must match the receipt detail total.', 16, 1);
            RETURN;
        END
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET AmountSpent = @AmountSpent,
        CurrentOwnerUserId = CASE WHEN @ShouldClaimFullCustody = 1 THEN @LiquidatingUserId ELSE CurrentOwnerUserId END,
        RemainingAmount = 0,
        LiquidationBaseAmount = @LiquidationBaseAmount,
        ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END,
        ExcessAmount = CASE
            WHEN @UsesPettyCashDetails = 1 THEN 0
            WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount
            ELSE 0
        END,
        LiquidationNotes = @Notes,
        RfpRequestNumber = NULL,
        RfpDecision = NULL,
        RfpWaiveReason = NULL,
        StatusId = 1,
        LiquidatedAt = GETDATE(),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND StatusId IN (0, 7)
      AND @LiquidationBaseAmount > 0
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.FMS_CashAdvanceTransfers pendingTransfer
          WHERE pendingTransfer.CashAdvanceRequestId = @CashAdvanceRequestId
            AND pendingTransfer.Status = 'pending'
      );

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Cash advance request is not ready for liquidation or has a pending transfer acknowledgement.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'liquidation_submitted', @ActorUserId, @AmountSpent, @Notes);

    DELETE FROM dbo.FMS_CashAdvanceRequests_Dtl
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    DELETE FROM dbo.FMS_PettyCashReceiptDetails
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    DELETE FROM dbo.FMS_PettyCashTransportationDetails
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @UsesPettyCashDetails = 1
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
        FROM #PettyCashReceiptRows;

        INSERT INTO dbo.FMS_PettyCashTransportationDetails
            (CashAdvanceRequestId, [Description], FromLocation, ToLocation, TransactionDate, Amount)
        SELECT @CashAdvanceRequestId,
               [Description],
               FromLocation,
               ToLocation,
               TransactionDate,
               Amount
        FROM #PettyCashTransportationRows;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceRequests_Dtl
            (CashAdvanceRequestId, VendorCode, [Description], ProjectCode, ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode)
        SELECT @CashAdvanceRequestId,
               VendorCode,
               [Description],
               ProjectCode,
               ProfitCenterCode,
               Amount,
               InvoiceRef,
               ExpenseTypeCode
        FROM #ReceiptRows;
    END

    IF ISJSON(@AttachmentsJson) = 1
    BEGIN
        IF @ReplaceExistingAttachments = 1
           AND EXISTS
           (
               SELECT 1
               FROM OPENJSON(@AttachmentsJson)
               WITH (OriginalFileName nvarchar(260) '$.OriginalFileName')
               WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> ''
           )
        BEGIN
            DELETE FROM dbo.FMS_CashAdvanceAttachments
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;
        END

        INSERT INTO dbo.FMS_CashAdvanceAttachments
            (CashAdvanceRequestId, FileName, OriginalFileName, StoredFileName, RelativePath, ContentType, FileSizeBytes)
        SELECT @CashAdvanceRequestId,
               OriginalFileName,
               OriginalFileName,
               StoredFileName,
               RelativePath,
               ContentType,
               FileSizeBytes
        FROM OPENJSON(@AttachmentsJson)
        WITH
        (
            OriginalFileName nvarchar(260) '$.OriginalFileName',
            StoredFileName nvarchar(260) '$.StoredFileName',
            RelativePath nvarchar(500) '$.RelativePath',
            ContentType nvarchar(100) '$.ContentType',
            FileSizeBytes bigint '$.FileSizeBytes'
        )
        WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> '';
    END
END
GO
