SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CompanyCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CompanyCode nvarchar(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests', N'CompanyID') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests ADD CompanyID int NULL;
END
GO

IF OBJECT_ID(N'FineReport..New_ORFP_Hdr', N'U') IS NOT NULL
BEGIN
    UPDATE targetRequest
    SET CompanyID = TRY_CONVERT(int, sourceHeader.CompanyID)
    FROM dbo.FMS_CashAdvanceRequests targetRequest
    INNER JOIN FineReport..New_ORFP_Hdr sourceHeader
        ON targetRequest.RfpRequestNumber = CONVERT(nvarchar(50), sourceHeader.RF_Number)
    WHERE TRY_CONVERT(int, sourceHeader.CompanyID) IS NOT NULL
      AND (targetRequest.CompanyID IS NULL
           OR targetRequest.CompanyID <> TRY_CONVERT(int, sourceHeader.CompanyID));

    WHILE EXISTS
    (
        SELECT 1
        FROM dbo.FMS_CashAdvanceRequests childRequest
        INNER JOIN dbo.FMS_CashAdvanceRequests parentRequest
            ON parentRequest.CashAdvanceRequestId = childRequest.OriginalCashAdvanceRequestId
        WHERE childRequest.CompanyID IS NULL
          AND parentRequest.CompanyID IS NOT NULL
    )
    BEGIN
        UPDATE childRequest
        SET CompanyID = parentRequest.CompanyID
        FROM dbo.FMS_CashAdvanceRequests childRequest
        INNER JOIN dbo.FMS_CashAdvanceRequests parentRequest
            ON parentRequest.CashAdvanceRequestId = childRequest.OriginalCashAdvanceRequestId
        WHERE childRequest.CompanyID IS NULL
          AND parentRequest.CompanyID IS NOT NULL;
    END;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_GetRequest
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF OBJECT_ID(N'FineReport..New_ORFP_Hdr', N'U') IS NULL
       OR OBJECT_ID(N'FineReport..New_ORFP_Dtl', N'U') IS NULL
       OR OBJECT_ID(N'dbo.FMS_CashAdvanceRequests', N'U') IS NULL
       OR OBJECT_ID(N'dbo.FMS_CashAdvanceRequests_Dtl', N'U') IS NULL
       OR OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
       OR OBJECT_ID(N'dbo.vw_FMS_Company', N'V') IS NULL
    BEGIN
        THROW 51150, 'Required FineReport or FMS request tables were not found.', 1;
    END;

    DECLARE @InsertedUsers int = 0;
    DECLARE @InsertedRequests int = 0;
    DECLARE @InsertedDetails int = 0;
    DECLARE @CompanyObjectId int = OBJECT_ID(N'dbo.vw_FMS_Company', N'V');
    DECLARE @CompanyIdColumn sysname = NULL;
    DECLARE @CompanyCodeColumn sysname = NULL;

    SELECT TOP (1) @CompanyIdColumn = [name]
    FROM sys.columns
    WHERE [object_id] = @CompanyObjectId
      AND [name] IN (N'ID', N'Id', N'CompanyId', N'CompanyID', N'CompanyCode', N'Code')
    ORDER BY CASE [name]
        WHEN N'ID' THEN 1
        WHEN N'Id' THEN 2
        WHEN N'CompanyId' THEN 3
        WHEN N'CompanyID' THEN 4
        WHEN N'CompanyCode' THEN 5
        WHEN N'Code' THEN 6
        ELSE 7
    END;

    SELECT TOP (1) @CompanyCodeColumn = [name]
    FROM sys.columns
    WHERE [object_id] = @CompanyObjectId
      AND [name] IN (N'CompanyCode', N'Code')
    ORDER BY CASE [name]
        WHEN N'CompanyCode' THEN 1
        WHEN N'Code' THEN 2
        ELSE 3
    END;

    IF @CompanyIdColumn IS NULL OR @CompanyCodeColumn IS NULL
    BEGIN
        THROW 51153, 'vw_FMS_Company must expose a company ID and company code column.', 1;
    END;

    BEGIN TRY
        IF OBJECT_ID(N'dbo.sp_AppUsers_ImportFineReportRequestors', N'P') IS NOT NULL
        BEGIN
            EXEC dbo.sp_AppUsers_ImportFineReportRequestors;
        END;

        BEGIN TRANSACTION;

        CREATE TABLE #Headers
        (
            RFNumber int NOT NULL PRIMARY KEY,
            RequestorSourceID nvarchar(50) COLLATE DATABASE_DEFAULT NOT NULL,
            RequestorEmail nvarchar(320) COLLATE DATABASE_DEFAULT NOT NULL,
            DepartmentCode int NOT NULL,
            DepartmentName nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
            CompanyID int NULL,
            CompanyCode nvarchar(50) COLLATE DATABASE_DEFAULT NULL,
            TotalAmount decimal(19,4) NOT NULL,
            Purpose nvarchar(500) COLLATE DATABASE_DEFAULT NOT NULL,
            SourceAuditDate datetime NOT NULL
        );

        INSERT INTO #Headers
            (RFNumber, RequestorSourceID, RequestorEmail, DepartmentCode, DepartmentName, CompanyID, TotalAmount, Purpose, SourceAuditDate)
        SELECT sourceHeader.RF_Number,
               LTRIM(RTRIM(CONVERT(nvarchar(50), sourceHeader.RequestorID))),
               LOWER(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceRequestor.EmailAddress)))),
               department.DepartmentCode,
               department.DepartmentName,
               TRY_CONVERT(int, sourceHeader.CompanyID),
               CONVERT(decimal(19,4), sourceHeader.TotalAmount),
               LTRIM(RTRIM(CONVERT(nvarchar(500), sourceHeader.PurOfDisbursement))),
               sourceHeader.AuditDate
        FROM FineReport..New_ORFP_Hdr sourceHeader
        INNER JOIN FineReport..FineReport_RFP_Requestor sourceRequestor
            ON sourceRequestor.RequestorID = sourceHeader.RequestorID
        INNER JOIN dbo.FMS_Departments department
            ON department.DepartmentCode = TRY_CONVERT(int, sourceHeader.ReqGroup)
        WHERE sourceHeader.TypeOfExpense = N'3'
          AND sourceHeader.[Status] = N'1'
          AND sourceHeader.PurOfDisbursement NOT LIKE N'%Company loan%';

        DECLARE @CompanyLookupSql nvarchar(max) = N'
        WITH Companies AS
        (
            SELECT TRY_CONVERT(int, ' + QUOTENAME(@CompanyIdColumn) + N') AS CompanyID,
                   NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), ' + QUOTENAME(@CompanyCodeColumn) + N') COLLATE DATABASE_DEFAULT)), N'''') AS CompanyCode
            FROM dbo.vw_FMS_Company
        )
        UPDATE sourceHeader
        SET CompanyCode = company.CompanyCode
        FROM #Headers sourceHeader
        CROSS APPLY
        (
            SELECT TOP (1) companyRow.CompanyCode
            FROM Companies companyRow
            WHERE companyRow.CompanyID = sourceHeader.CompanyID
              AND companyRow.CompanyCode IS NOT NULL
            ORDER BY companyRow.CompanyCode
        ) company;';

        EXEC sys.sp_executesql @CompanyLookupSql;

        IF EXISTS
        (
            SELECT 1
            FROM FineReport..New_ORFP_Hdr sourceHeader
            WHERE sourceHeader.TypeOfExpense = N'3'
              AND sourceHeader.[Status] = N'1'
              AND sourceHeader.PurOfDisbursement NOT LIKE N'%Company loan%'
              AND
              (
                  NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), sourceHeader.RequestorID))), N'') IS NULL
                  OR TRY_CONVERT(int, sourceHeader.CompanyID) IS NULL
                  OR NOT EXISTS
                  (
                      SELECT 1
                      FROM FineReport..FineReport_RFP_Requestor sourceRequestor
                      INNER JOIN dbo.FMS_AppUsers appUser
                          ON appUser.Email = LOWER(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceRequestor.EmailAddress))))
                      WHERE sourceRequestor.RequestorID = sourceHeader.RequestorID
                  )
                  OR sourceHeader.TotalAmount IS NULL
                  OR sourceHeader.TotalAmount <= 0
                  OR NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.FMS_Departments department
                      WHERE department.DepartmentCode = TRY_CONVERT(int, sourceHeader.ReqGroup)
                  )
              )
        )
        BEGIN
            THROW 51151, 'An eligible FineReport header has an invalid requestor, company, amount, or department group.', 1;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM #Headers
            WHERE CompanyID IS NULL
               OR CompanyCode IS NULL
        )
        BEGIN
            THROW 51154, 'One or more FineReport CompanyID values could not be mapped to vw_FMS_Company.CompanyCode.', 1;
        END;

        CREATE TABLE #ResolvedRequestors
        (
            RequestorSourceID nvarchar(50) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
            RequestorEmail nvarchar(320) COLLATE DATABASE_DEFAULT NOT NULL,
            UserID int NOT NULL
        );

        INSERT INTO #ResolvedRequestors (RequestorSourceID, RequestorEmail, UserID)
        SELECT sourceHeader.RequestorSourceID,
               sourceHeader.RequestorEmail,
               MIN(appUser.UserId)
        FROM #Headers sourceHeader
        INNER JOIN dbo.FMS_AppUsers appUser
            ON appUser.Email = sourceHeader.RequestorEmail
        GROUP BY sourceHeader.RequestorSourceID, sourceHeader.RequestorEmail;

        IF (SELECT COUNT(DISTINCT RequestorSourceID) FROM #Headers) <> (SELECT COUNT(*) FROM #ResolvedRequestors)
        BEGIN
            THROW 51152, 'One or more FineReport RequestorID values could not be resolved through EmailAddress to FMS_AppUsers.', 1;
        END;

        INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode, DepartmentGroup)
        SELECT DISTINCT resolvedRequestor.UserID,
               sourceHeader.DepartmentCode,
               TRY_CONVERT(int, department.DepartmentGroup)
        FROM #Headers sourceHeader
        INNER JOIN #ResolvedRequestors resolvedRequestor
            ON resolvedRequestor.RequestorSourceID = sourceHeader.RequestorSourceID
        INNER JOIN dbo.FMS_AppUsers requestorUser
            ON requestorUser.UserId = resolvedRequestor.UserID
           AND requestorUser.RoleCode = 2
        INNER JOIN dbo.FMS_Departments department
            ON department.DepartmentCode = sourceHeader.DepartmentCode
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_ApproverDepartments existingAssignment
            WHERE existingAssignment.UserID = resolvedRequestor.UserID
              AND existingAssignment.DepartmentCode = sourceHeader.DepartmentCode
        );

        UPDATE targetRequest
        SET CurrentOwnerUserId = CASE
                WHEN targetRequest.CurrentOwnerUserId IS NULL
                  OR targetRequest.CurrentOwnerUserId = targetRequest.RequestorUserId
                THEN resolvedRequestor.UserID
                ELSE targetRequest.CurrentOwnerUserId
            END,
            CompanyID = sourceHeader.CompanyID,
            CompanyCode = sourceHeader.CompanyCode,
            RequestorUserId = resolvedRequestor.UserID,
            UpdatedAt = GETDATE()
        FROM dbo.FMS_CashAdvanceRequests targetRequest
        INNER JOIN #Headers sourceHeader
            ON targetRequest.RfpRequestNumber = CONVERT(nvarchar(50), sourceHeader.RFNumber)
        INNER JOIN #ResolvedRequestors resolvedRequestor
            ON resolvedRequestor.RequestorSourceID = sourceHeader.RequestorSourceID
        WHERE targetRequest.RequestorUserId <> resolvedRequestor.UserID
           OR COALESCE(targetRequest.CompanyID, -1) <> COALESCE(sourceHeader.CompanyID, -1)
           OR COALESCE(targetRequest.CompanyCode, N'') <> COALESCE(sourceHeader.CompanyCode, N'');

        INSERT INTO dbo.FMS_CashAdvanceRequests
            (RequestNumber, RequestorUserId, Department, Amount, Purpose, RfpRequestNumber,
             CompanyID, CompanyCode, DueDate, CurrentOwnerUserId, RemainingAmount, StatusId, AuditDate, RequestType)
        SELECT CONCAT(N'RFP-', sourceHeader.RFNumber),
               resolvedRequestor.UserID,
               sourceHeader.DepartmentName,
               sourceHeader.TotalAmount,
               sourceHeader.Purpose,
               CONVERT(nvarchar(50), sourceHeader.RFNumber),
               sourceHeader.CompanyID,
               sourceHeader.CompanyCode,
               DATEADD(DAY, 7, CONVERT(date, sourceHeader.SourceAuditDate)),
               resolvedRequestor.UserID,
               sourceHeader.TotalAmount,
               0,
               sourceHeader.SourceAuditDate,
               N'cash_advance'
        FROM #Headers sourceHeader
        INNER JOIN #ResolvedRequestors resolvedRequestor
            ON resolvedRequestor.RequestorSourceID = sourceHeader.RequestorSourceID
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_CashAdvanceRequests existingRequest
            WHERE existingRequest.RequestNumber = CONCAT(N'RFP-', sourceHeader.RFNumber)
               OR existingRequest.RfpRequestNumber = CONVERT(nvarchar(50), sourceHeader.RFNumber)
        );

        SET @InsertedRequests = @@ROWCOUNT;

        INSERT INTO dbo.FMS_CashAdvanceRequests_Dtl
            (CashAdvanceRequestId, VendorCode, [Description], ProjectCode,
             ProfitCenterCode, Amount, InvoiceRef, ExpenseTypeCode, AuditDate)
        SELECT targetRequest.CashAdvanceRequestId,
               CONVERT(varchar(50), COALESCE(
                   NULLIF(LTRIM(RTRIM(sourceDetail.VendorCode)), N''),
                   NULLIF(LTRIM(RTRIM(sourceHeader.PayeeCode)), N''),
                   N'UNKNOWN'
               )),
               CONVERT(nvarchar(500), COALESCE(
                   NULLIF(LTRIM(RTRIM(sourceDetail.[Description])), N''),
                   NULLIF(LTRIM(RTRIM(sourceDetail.Remarks)), N''),
                   NULLIF(LTRIM(RTRIM(sourceHeader.PurOfDisbursement)), N''),
                   N'Imported FineReport detail'
               )),
               CONVERT(nvarchar(20), COALESCE(NULLIF(LTRIM(RTRIM(sourceDetail.Proj_Code)), N''), N'N/A')),
               CONVERT(nvarchar(8), COALESCE(NULLIF(LTRIM(RTRIM(sourceDetail.CostCenter)), N''), N'N/A')),
               CONVERT(decimal(19,4), sourceDetail.Amount),
               CONVERT(nvarchar(100), COALESCE(
                   NULLIF(LTRIM(RTRIM(sourceDetail.Bill_Ref)), N''),
                   NULLIF(LTRIM(RTRIM(sourceDetail.Int_Ref)), N''),
                   NULLIF(LTRIM(RTRIM(sourceDetail.SAP_RefNo)), N''),
                   N'N/A'
               )),
               CONVERT(varchar(50), COALESCE(NULLIF(LTRIM(RTRIM(sourceDetail.CapexOpex)), N''), N'3')),
               sourceDetail.AuditDate
        FROM FineReport..New_ORFP_Dtl sourceDetail
        INNER JOIN FineReport..New_ORFP_Hdr sourceHeader
            ON CONVERT(varchar(100), sourceHeader.RF_Number) = sourceDetail.RF_Number
        INNER JOIN dbo.FMS_CashAdvanceRequests targetRequest
            ON targetRequest.RfpRequestNumber = CONVERT(nvarchar(50), sourceHeader.RF_Number)
        WHERE sourceHeader.TypeOfExpense = N'3'
          AND sourceHeader.[Status] = N'1'
          AND sourceHeader.PurOfDisbursement NOT LIKE N'%Company loan%'
          AND sourceDetail.Amount IS NOT NULL
          AND sourceDetail.Amount > 0
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FMS_CashAdvanceRequests_Dtl existingDetail
              WHERE existingDetail.CashAdvanceRequestId = targetRequest.CashAdvanceRequestId
                AND existingDetail.VendorCode = CONVERT(varchar(50), COALESCE(
                    NULLIF(LTRIM(RTRIM(sourceDetail.VendorCode)), N''),
                    NULLIF(LTRIM(RTRIM(sourceHeader.PayeeCode)), N''), N'UNKNOWN'))
                AND existingDetail.ProjectCode = CONVERT(nvarchar(20), COALESCE(NULLIF(LTRIM(RTRIM(sourceDetail.Proj_Code)), N''), N'N/A'))
                AND existingDetail.ProfitCenterCode = CONVERT(nvarchar(8), COALESCE(NULLIF(LTRIM(RTRIM(sourceDetail.CostCenter)), N''), N'N/A'))
                AND existingDetail.Amount = CONVERT(decimal(19,4), sourceDetail.Amount)
                AND existingDetail.InvoiceRef = CONVERT(nvarchar(100), COALESCE(
                    NULLIF(LTRIM(RTRIM(sourceDetail.Bill_Ref)), N''),
                    NULLIF(LTRIM(RTRIM(sourceDetail.Int_Ref)), N''),
                    NULLIF(LTRIM(RTRIM(sourceDetail.SAP_RefNo)), N''), N'N/A'))
                AND existingDetail.[Description] = CONVERT(nvarchar(500), COALESCE(
                    NULLIF(LTRIM(RTRIM(sourceDetail.[Description])), N''),
                    NULLIF(LTRIM(RTRIM(sourceDetail.Remarks)), N''),
                    NULLIF(LTRIM(RTRIM(sourceHeader.PurOfDisbursement)), N''),
                    N'Imported FineReport detail'))
          );

        SET @InsertedDetails = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT @InsertedUsers AS InsertedUsers,
               @InsertedRequests AS InsertedRequests,
               @InsertedDetails AS InsertedDetails,
               (SELECT COUNT(*) FROM #Headers) AS EligibleHeaders;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ;THROW;
END CATCH;
END
GO

DECLARE @GetForUserDefinition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_GetForUser'));
DECLARE @GetForUserProcedureIndex int;

IF @GetForUserDefinition IS NOT NULL
   AND @GetForUserDefinition NOT LIKE N'%r.CompanyID,%'
BEGIN
    IF @GetForUserDefinition NOT LIKE N'%r.CvNumber,%'
    BEGIN
        THROW 51155, 'Could not add CompanyID to sp_CashAdvanceRequests_GetForUser.', 1;
    END;

    SET @GetForUserDefinition = REPLACE(
        @GetForUserDefinition,
        N'r.CvNumber,',
        N'r.CvNumber,
           r.CompanyID,');

    SET @GetForUserProcedureIndex = PATINDEX(N'%PROCEDURE%', @GetForUserDefinition);

    IF @GetForUserProcedureIndex <= 0
    BEGIN
        THROW 51156, 'Could not locate the procedure keyword for sp_CashAdvanceRequests_GetForUser.', 1;
    END;

    SET @GetForUserDefinition = STUFF(@GetForUserDefinition, 1, @GetForUserProcedureIndex - 1, N'ALTER ');
    EXEC sys.sp_executesql @GetForUserDefinition;
END
GO

DECLARE @TransferResponseDefinition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_TransferResponse'));
DECLARE @TransferResponseProcedureIndex int;

IF @TransferResponseDefinition IS NOT NULL
   AND @TransferResponseDefinition NOT LIKE N'%DECLARE @CompanyID int;%'
BEGIN
    IF @TransferResponseDefinition NOT LIKE N'%DECLARE @CompanyCode nvarchar(50);%'
       OR @TransferResponseDefinition NOT LIKE N'%@DueDate = r.DueDate,%'
       OR @TransferResponseDefinition NOT LIKE N'%Department, CompanyCode, Amount%'
       OR @TransferResponseDefinition NOT LIKE N'%@ReceiverDepartment, @CompanyCode, @PendingTransferAmount%'
    BEGIN
        THROW 51157, 'Could not add CompanyID inheritance to sp_CashAdvanceRequests_TransferResponse.', 1;
    END;

    SET @TransferResponseDefinition = REPLACE(
        @TransferResponseDefinition,
        N'DECLARE @CompanyCode nvarchar(50);',
        N'DECLARE @CompanyID int;
    DECLARE @CompanyCode nvarchar(50);');

    SET @TransferResponseDefinition = REPLACE(
        @TransferResponseDefinition,
        N'@DueDate = r.DueDate,',
        N'@DueDate = r.DueDate,
           @CompanyID = r.CompanyID,');

    SET @TransferResponseDefinition = REPLACE(
        @TransferResponseDefinition,
        N'Department, CompanyCode, Amount',
        N'Department, CompanyID, CompanyCode, Amount');

    SET @TransferResponseDefinition = REPLACE(
        @TransferResponseDefinition,
        N'@ReceiverDepartment, @CompanyCode, @PendingTransferAmount',
        N'@ReceiverDepartment, @CompanyID, @CompanyCode, @PendingTransferAmount');

    SET @TransferResponseProcedureIndex = PATINDEX(N'%PROCEDURE%', @TransferResponseDefinition);

    IF @TransferResponseProcedureIndex <= 0
    BEGIN
        THROW 51158, 'Could not locate the procedure keyword for sp_CashAdvanceRequests_TransferResponse.', 1;
    END;

    SET @TransferResponseDefinition = STUFF(@TransferResponseDefinition, 1, @TransferResponseProcedureIndex - 1, N'ALTER ');
    EXEC sys.sp_executesql @TransferResponseDefinition;
END
GO
