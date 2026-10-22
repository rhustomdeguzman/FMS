USE FMS;
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RfpRequestNumber') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RfpRequestNumber nvarchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RfpDecision') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RfpDecision nvarchar(20) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'RfpWaiveReason') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD RfpWaiveReason nvarchar(1000) NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_CashAdvanceRequests_Status')
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests DROP CONSTRAINT CK_CashAdvanceRequests_Status;
END
GO

ALTER TABLE dbo.FMS_CashAdvanceRequests
ADD CONSTRAINT CK_CashAdvanceRequests_Status CHECK (Status IN
(
    'pending_liquidation',
    'pending_department_approval',
    'pending_cashier_return',
    'pending_cashier_closure',
    'pending_accounting_review',
    'pending_rfp_department_approval',
    'pending_rfp_attachment',
    'partially_liquidated',
    'fully_liquidated',
    'transferred',
    'rfp_created',
    'rejected'
));
GO

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
    DECLARE @LiquidatingUserRoleCode int;
    DECLARE @ShouldClaimFullCustody bit = 0;

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @LiquidationBaseAmount = COALESCE(RemainingAmount, Amount),
           @RequestDepartment = Department
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
            THROW 51000, 'Only the current owner or department approver can submit liquidation.', 1;
        END
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET AmountSpent = @AmountSpent,
        CurrentOwnerUserId = CASE WHEN @ShouldClaimFullCustody = 1 THEN @LiquidatingUserId ELSE CurrentOwnerUserId END,
        RemainingAmount = 0,
        LiquidationBaseAmount = @LiquidationBaseAmount,
        ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END,
        ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END,
        LiquidationNotes = @Notes,
        RfpRequestNumber = NULL,
        RfpDecision = NULL,
        RfpWaiveReason = NULL,
        Status = 'pending_department_approval',
        LiquidatedAt = GETDATE(),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND Status IN ('pending_liquidation', 'partially_liquidated')
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
        THROW 51000, 'Cash advance request is not ready for liquidation or has a pending transfer acknowledgement.', 1;
    END

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'liquidation_submitted', @ActorUserId, @AmountSpent, @Notes);

    DELETE FROM dbo.FMS_CashAdvanceRequests_Dtl
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    IF ISJSON(@ReceiptDetailsJson) = 1
    BEGIN
        INSERT INTO dbo.FMS_CashAdvanceRequests_Dtl
            (CashAdvanceRequestId, Vendor, [Description], Project, ProfitCenter, Amount, InvoiceRef, ExpenseType)
        SELECT @CashAdvanceRequestId,
               Vendor,
               [Description],
               Project,
               ProfitCenter,
               Amount,
               InvoiceRef,
               ExpenseType
        FROM OPENJSON(@ReceiptDetailsJson)
        WITH
        (
            Vendor nvarchar(200) '$.Vendor',
            [Description] nvarchar(500) '$.Description',
            Project nvarchar(200) '$.Project',
            ProfitCenter nvarchar(200) '$.ProfitCenter',
            Amount decimal(19,4) '$.Amount',
            InvoiceRef nvarchar(100) '$.InvoiceRef',
            ExpenseType nvarchar(100) '$.ExpenseType'
        )
        WHERE Vendor IS NOT NULL AND LTRIM(RTRIM(Vendor)) <> ''
          AND [Description] IS NOT NULL AND LTRIM(RTRIM([Description])) <> ''
          AND Project IS NOT NULL AND LTRIM(RTRIM(Project)) <> ''
          AND ProfitCenter IS NOT NULL AND LTRIM(RTRIM(ProfitCenter)) <> ''
          AND Amount > 0
          AND InvoiceRef IS NOT NULL AND LTRIM(RTRIM(InvoiceRef)) <> ''
          AND ExpenseType IS NOT NULL AND LTRIM(RTRIM(ExpenseType)) <> '';
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_SubmitRfpAttachment
    @CashAdvanceRequestId int,
    @Notes nvarchar(max) = NULL,
    @AttachmentsJson nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentOwnerUserId int;
    DECLARE @ExcessAmount decimal(19,4);

    SELECT @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @ExcessAmount = ExcessAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId
      AND Status = 'pending_rfp_attachment'
      AND RfpDecision = 'create';

    IF @CurrentOwnerUserId IS NULL
    BEGIN
        THROW 51013, 'Cash advance request is not waiting for an RFP attachment.', 1;
    END

    IF ISJSON(@AttachmentsJson) <> 1
       OR NOT EXISTS
       (
           SELECT 1
           FROM OPENJSON(@AttachmentsJson)
           WITH (OriginalFileName nvarchar(260) '$.OriginalFileName')
           WHERE OriginalFileName IS NOT NULL AND LTRIM(RTRIM(OriginalFileName)) <> ''
       )
    BEGIN
        THROW 51014, 'RFP attachment is required.', 1;
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

    UPDATE dbo.FMS_CashAdvanceRequests
    SET Status = 'pending_accounting_review',
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId,
        'rfp_attachment_uploaded',
        @CurrentOwnerUserId,
        @ExcessAmount,
        COALESCE(@Notes, 'Requestor uploaded the RFP attachment for accounting review.')
    );
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_DepartmentDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL,
    @RfpDecision nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status nvarchar(50);
    DECLARE @AmountSpent decimal(19,4);
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @ReturnAmount decimal(19,4);
    DECLARE @ExcessAmount decimal(19,4);
    DECLARE @RequestNumber nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @CurrentOwnerUserId int;
    DECLARE @Department nvarchar(100);
    DECLARE @Purpose nvarchar(500);
    DECLARE @RfpRequestNumber nvarchar(50);
    DECLARE @RfpDecisionNormalized nvarchar(20);

    SELECT @Status = Status,
           @AmountSpent = AmountSpent,
           @LiquidationBaseAmount = COALESCE(LiquidationBaseAmount, Amount),
           @RequestNumber = RequestNumber,
           @RequestorUserId = RequestorUserId,
           @CurrentOwnerUserId = COALESCE(CurrentOwnerUserId, RequestorUserId),
           @Department = Department,
           @Purpose = Purpose,
           @ExcessAmount = ExcessAmount
    FROM dbo.FMS_CashAdvanceRequests
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @Status IS NULL
    BEGIN
        RETURN;
    END

    IF @Status = 'pending_rfp_department_approval'
    BEGIN
        IF @Approved = 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'pending_liquidation',
                RemainingAmount = COALESCE(NULLIF(LiquidationBaseAmount, 0), Amount),
                ReturnAmount = NULL,
                ExcessAmount = NULL,
                RfpDecision = NULL,
                RfpWaiveReason = NULL,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'returned',
                @ApproverUserId,
                @ExcessAmount,
                COALESCE(@Notes, 'Department returned the request for correction.')
            );

            RETURN;
        END

        IF ISNULL(@ExcessAmount, 0) <= 0
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'fully_liquidated',
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            RETURN;
        END

        SET @RfpDecisionNormalized = LOWER(LTRIM(RTRIM(COALESCE(@RfpDecision, N'create'))));

        IF @RfpDecisionNormalized NOT IN (N'create', N'waive')
        BEGIN
            THROW 51015, 'RFP decision must be Create RFP or Waive RFP.', 1;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            THROW 51016, 'Waive RFP reason is required.', 1;
        END

        IF @RfpDecisionNormalized = N'create'
        BEGIN
            SET @RfpRequestNumber = CONCAT(@RequestNumber, '-RFP-', @CashAdvanceRequestId);

            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'pending_rfp_attachment',
                RfpRequestNumber = @RfpRequestNumber,
                RfpDecision = 'create',
                RfpWaiveReason = NULL,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'rfp_created',
                @ApproverUserId,
                @ExcessAmount,
                COALESCE(@Notes, 'Department approved RFP creation. Requestor must upload the RFP attachment.')
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.FMS_CashAdvanceRequests
            SET Status = 'fully_liquidated',
                RfpDecision = 'waive',
                RfpWaiveReason = @Notes,
                UpdatedAt = GETDATE()
            WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

            INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
            VALUES
            (
                @CashAdvanceRequestId,
                'rfp_waived',
                @ApproverUserId,
                @ExcessAmount,
                @Notes
            );
        END

        RETURN;
    END

    IF @Status <> 'pending_department_approval'
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET Status = 'pending_liquidation',
            RemainingAmount = COALESCE(NULLIF(LiquidationBaseAmount, 0), Amount),
            ReturnAmount = NULL,
            ExcessAmount = NULL,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'returned',
            @ApproverUserId,
            @AmountSpent,
            COALESCE(@Notes, 'Department returned the request for correction.')
        );

        RETURN;
    END

    SET @ReturnAmount = CASE WHEN @LiquidationBaseAmount > @AmountSpent THEN @LiquidationBaseAmount - @AmountSpent ELSE 0 END;
    SET @ExcessAmount = CASE WHEN @AmountSpent > @LiquidationBaseAmount THEN @AmountSpent - @LiquidationBaseAmount ELSE 0 END;

    IF ISNULL(@ExcessAmount, 0) > 0
    BEGIN
        SET @RfpDecisionNormalized = LOWER(LTRIM(RTRIM(COALESCE(@RfpDecision, N'create'))));

        IF @RfpDecisionNormalized NOT IN (N'create', N'waive')
        BEGIN
            THROW 51015, 'RFP decision must be Create RFP or Waive RFP.', 1;
        END

        IF @RfpDecisionNormalized = N'waive' AND NULLIF(LTRIM(RTRIM(COALESCE(@Notes, N''))), N'') IS NULL
        BEGIN
            THROW 51016, 'Waive RFP reason is required.', 1;
        END

        IF @RfpDecisionNormalized = N'create'
        BEGIN
            SET @RfpRequestNumber = CONCAT(@RequestNumber, '-RFP-', @CashAdvanceRequestId);
        END

        UPDATE dbo.FMS_CashAdvanceRequests
        SET Status = CASE
                WHEN @RfpDecisionNormalized = N'create' THEN 'pending_rfp_attachment'
                ELSE 'pending_accounting_review'
            END,
            ReturnAmount = NULL,
            ExcessAmount = @ExcessAmount,
            RfpRequestNumber = CASE WHEN @RfpDecisionNormalized = N'create' THEN @RfpRequestNumber ELSE RfpRequestNumber END,
            RfpDecision = @RfpDecisionNormalized,
            RfpWaiveReason = CASE WHEN @RfpDecisionNormalized = N'waive' THEN @Notes ELSE NULL END,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES (@CashAdvanceRequestId, 'approved_by_department_head', @ApproverUserId, @AmountSpent, @Notes);

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            CASE WHEN @RfpDecisionNormalized = N'create' THEN 'rfp_created' ELSE 'rfp_waived' END,
            @ApproverUserId,
            @ExcessAmount,
            CASE
                WHEN @RfpDecisionNormalized = N'create' THEN COALESCE(@Notes, 'Department approved RFP creation. Requestor must upload the RFP attachment.')
                ELSE @Notes
            END
        );

        RETURN;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET Status = CASE
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 'pending_cashier_return'
            ELSE 'pending_accounting_review'
        END,
        ReturnAmount = NULLIF(@ReturnAmount, 0),
        ExcessAmount = NULLIF(@ExcessAmount, 0),
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'approved_by_department_head', @ApproverUserId, @AmountSpent, @Notes);
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_AccountingDecision
    @CashAdvanceRequestId int,
    @ApproverUserId int,
    @Approved bit,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExcessAmount decimal(19,4);
    DECLARE @ReturnAmount decimal(19,4);
    DECLARE @Amount decimal(19,4);
    DECLARE @AmountSpent decimal(19,4);
    DECLARE @LiquidationBaseAmount decimal(19,4);
    DECLARE @HasCashierReceipt bit;
    DECLARE @RfpDecision nvarchar(20);
    DECLARE @HasRfpAttachment bit;

    SELECT @ExcessAmount = ExcessAmount,
           @ReturnAmount = ReturnAmount,
           @Amount = Amount,
           @AmountSpent = AmountSpent,
           @LiquidationBaseAmount = COALESCE(LiquidationBaseAmount, Amount),
           @RfpDecision = RfpDecision,
           @HasRfpAttachment = CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM dbo.FMS_CashAdvanceAttachments attachment
                   WHERE attachment.CashAdvanceRequestId = r.CashAdvanceRequestId
                     AND attachment.RelativePath LIKE N'rfp/%'
               ) THEN 1
               ELSE 0
           END,
           @HasCashierReceipt = CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receipt
                   WHERE receipt.CashAdvanceRequestId = r.CashAdvanceRequestId
               ) THEN 1
               ELSE 0
           END
    FROM dbo.FMS_CashAdvanceRequests r
    WHERE r.CashAdvanceRequestId = @CashAdvanceRequestId
      AND Status = 'pending_accounting_review';

    IF @Amount IS NULL
    BEGIN
        RETURN;
    END

    IF @Approved = 0
    BEGIN
        UPDATE dbo.FMS_CashAdvanceRequests
        SET Status = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN 'pending_rfp_attachment'
                ELSE 'pending_liquidation'
            END,
            RemainingAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN RemainingAmount
                ELSE COALESCE(NULLIF(@LiquidationBaseAmount, 0), @Amount)
            END,
            ReturnAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN ReturnAmount
                ELSE NULL
            END,
            ExcessAmount = CASE
                WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' THEN ExcessAmount
                ELSE NULL
            END,
            UpdatedAt = GETDATE()
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

        INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
        VALUES
        (
            @CashAdvanceRequestId,
            'returned',
            @ApproverUserId,
            @AmountSpent,
            COALESCE(@Notes, 'Accounting returned the request for correction.')
        );

        RETURN;
    END

    IF ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision = N'create' AND ISNULL(@HasRfpAttachment, 0) = 0
    BEGIN
        THROW 51017, 'RFP attachment is required before accounting approval.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET Status = CASE
            WHEN ISNULL(@ExcessAmount, 0) > 0 AND @RfpDecision IS NULL THEN 'pending_rfp_department_approval'
            WHEN ISNULL(@ReturnAmount, 0) > 0 AND ISNULL(@HasCashierReceipt, 0) = 0 THEN 'pending_cashier_return'
            WHEN ISNULL(@ReturnAmount, 0) > 0 THEN 'pending_cashier_closure'
            ELSE 'fully_liquidated'
        END,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES (@CashAdvanceRequestId, 'approved_by_accounting', @ApproverUserId, @AmountSpent, @Notes);
END
GO
