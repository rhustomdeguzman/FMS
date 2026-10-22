SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
   OR OBJECT_ID(N'FineReport..FineReport_RFP_Approvers', N'U') IS NULL
BEGIN
    THROW 51130, 'Required FMS or FineReport tables were not found.', 1;
END
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.FMS_AppUsers', N'Email') IS NULL
    BEGIN
        ALTER TABLE dbo.FMS_AppUsers ADD Email nvarchar(320) NULL;
    END;

    IF COL_LENGTH(N'dbo.FMS_ApproverDepartments', N'DepartmentGroup') IS NULL
    BEGIN
        ALTER TABLE dbo.FMS_ApproverDepartments ADD DepartmentGroup int NULL;
    END;

    CREATE TABLE #SourceApprovers
    (
        IdentityKey nvarchar(400) COLLATE DATABASE_DEFAULT NOT NULL,
        Email nvarchar(320) COLLATE DATABASE_DEFAULT NULL,
        DisplayName nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
        Username nvarchar(50) COLLATE DATABASE_DEFAULT NOT NULL,
        Title nvarchar(100) COLLATE DATABASE_DEFAULT NOT NULL,
        DepartmentCode int NOT NULL,
        DepartmentGroup int NULL
    );

    INSERT INTO #SourceApprovers
        (IdentityKey, Email, DisplayName, Username, Title, DepartmentCode, DepartmentGroup)
    SELECT COALESCE(
               LOWER(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceRow.Email))), N'')),
               CONCAT(N'username:', LOWER(LTRIM(RTRIM(CONVERT(nvarchar(50), sourceRow.ApprvCode)))))
           ),
           LOWER(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceRow.Email))), N'')),
           NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(CONVERT(nvarchar(200), sourceRow.DisplayName), CHAR(13), N''), CHAR(10), N''))), N''),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(50), sourceRow.ApprvCode))), N''),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(100), sourceRow.Alias))), N''),
           TRY_CONVERT(int, sourceRow.ID),
           TRY_CONVERT(int, sourceRow.DeptGroup)
    FROM FineReport..FineReport_RFP_Approvers sourceRow
    WHERE sourceRow.RoleCode = N'H'
      AND sourceRow.Active = N'1';

    IF EXISTS
    (
        SELECT 1
        FROM #SourceApprovers
        WHERE DisplayName IS NULL OR Username IS NULL OR Title IS NULL OR DepartmentCode IS NULL
    )
    BEGIN
        THROW 51131, 'FineReport contains an approver with incomplete identity or department data.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM #SourceApprovers
        GROUP BY IdentityKey, DepartmentCode
        HAVING COUNT(DISTINCT COALESCE(DepartmentGroup, -2147483648)) > 1
    )
    BEGIN
        THROW 51132, 'FineReport contains conflicting department groups for the same approver and department.', 1;
    END;

    CREATE TABLE #IdentityUsers
    (
        IdentityKey nvarchar(400) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
        KeeperUserID int NOT NULL
    );

    ;WITH RankedIdentity AS
    (
        SELECT sourceApprover.*,
               ROW_NUMBER() OVER
               (
                   PARTITION BY sourceApprover.IdentityKey
                   ORDER BY sourceApprover.DepartmentCode DESC, sourceApprover.Username
               ) AS RowNumber
        FROM #SourceApprovers sourceApprover
    )
    INSERT INTO dbo.FMS_AppUsers
        (Username, DisplayName, Email, Title, RoleCode, PasswordHash, PettyCashFundAmount)
    SELECT COALESCE(representative.Email, representative.Username),
           representative.DisplayName,
           representative.Email,
           representative.Title,
           3,
           HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123')),
           NULL
    FROM RankedIdentity representative
    WHERE representative.RowNumber = 1
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.FMS_AppUsers existingUser
          INNER JOIN #SourceApprovers matchingSource
              ON matchingSource.IdentityKey = representative.IdentityKey
             AND matchingSource.DisplayName = LTRIM(RTRIM(REPLACE(REPLACE(existingUser.DisplayName, CHAR(13), N''), CHAR(10), N'')))
      );

    INSERT INTO #IdentityUsers (IdentityKey, KeeperUserID)
    SELECT sourceApprover.IdentityKey,
           MIN(appUser.UserId)
    FROM #SourceApprovers sourceApprover
    INNER JOIN dbo.FMS_AppUsers appUser
        ON LTRIM(RTRIM(REPLACE(REPLACE(appUser.DisplayName, CHAR(13), N''), CHAR(10), N''))) = sourceApprover.DisplayName
    GROUP BY sourceApprover.IdentityKey;

    IF (SELECT COUNT(DISTINCT IdentityKey) FROM #SourceApprovers)
       <> (SELECT COUNT(*) FROM #IdentityUsers)
    BEGIN
        THROW 51133, 'One or more FineReport approver identities could not be mapped to FMS_AppUsers.', 1;
    END;

    CREATE TABLE #UserMerge
    (
        UserID int NOT NULL PRIMARY KEY,
        KeeperUserID int NOT NULL,
        IdentityKey nvarchar(400) COLLATE DATABASE_DEFAULT NOT NULL
    );

    INSERT INTO #UserMerge (UserID, KeeperUserID, IdentityKey)
    SELECT DISTINCT appUser.UserId,
           identityUser.KeeperUserID,
           identityUser.IdentityKey
    FROM dbo.FMS_AppUsers appUser
    INNER JOIN #SourceApprovers sourceApprover
        ON sourceApprover.DisplayName = LTRIM(RTRIM(REPLACE(REPLACE(appUser.DisplayName, CHAR(13), N''), CHAR(10), N'')))
    INNER JOIN #IdentityUsers identityUser
        ON identityUser.IdentityKey = sourceApprover.IdentityKey;

    IF EXISTS
    (
        SELECT 1 FROM dbo.FMS_CashAdvanceRequests requestRow
        INNER JOIN #UserMerge mergeRow ON mergeRow.UserID <> mergeRow.KeeperUserID
            AND mergeRow.UserID IN
                (requestRow.RequestorUserId, requestRow.CurrentOwnerUserId, requestRow.CustodianUserId,
                 requestRow.PendingTransferFromUserId, requestRow.PendingTransferToUserId)
        UNION ALL
        SELECT 1 FROM dbo.FMS_CashAdvanceHistory historyRow
        INNER JOIN #UserMerge mergeRow ON mergeRow.UserID <> mergeRow.KeeperUserID
            AND mergeRow.UserID = historyRow.ActorUserId
        UNION ALL
        SELECT 1 FROM dbo.FMS_CashAdvanceAcknowledgementReceipts receiptRow
        INNER JOIN #UserMerge mergeRow ON mergeRow.UserID <> mergeRow.KeeperUserID
            AND mergeRow.UserID = receiptRow.CreatedByUserId
        UNION ALL
        SELECT 1 FROM dbo.FMS_CashAdvanceTransfers transferRow
        INNER JOIN #UserMerge mergeRow ON mergeRow.UserID <> mergeRow.KeeperUserID
            AND mergeRow.UserID IN (transferRow.FromUserId, transferRow.ToUserId)
        UNION ALL
        SELECT 1 FROM dbo.FMS_Departments department
        INNER JOIN #UserMerge mergeRow ON mergeRow.UserID <> mergeRow.KeeperUserID
            AND mergeRow.UserID = department.CustodianUserId
    )
    BEGIN
        THROW 51134, 'A duplicate approver user already owns workflow data and cannot be merged automatically.', 1;
    END;

    ;WITH RankedIdentity AS
    (
        SELECT sourceApprover.*,
               ROW_NUMBER() OVER
               (
                   PARTITION BY sourceApprover.IdentityKey
                   ORDER BY sourceApprover.DepartmentCode DESC, sourceApprover.Username
               ) AS RowNumber
        FROM #SourceApprovers sourceApprover
    )
    UPDATE keeper
    SET Username = COALESCE(representative.Email, representative.Username),
        DisplayName = representative.DisplayName,
        Email = representative.Email,
        Title = representative.Title,
        RoleCode = 3,
        IsActive = 1,
        UpdatedAt = GETDATE()
    FROM dbo.FMS_AppUsers keeper
    INNER JOIN #IdentityUsers identityUser ON identityUser.KeeperUserID = keeper.UserId
    INNER JOIN RankedIdentity representative
        ON representative.IdentityKey = identityUser.IdentityKey
       AND representative.RowNumber = 1;

    INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode, DepartmentGroup)
    SELECT DISTINCT identityUser.KeeperUserID,
           sourceApprover.DepartmentCode,
           sourceApprover.DepartmentGroup
    FROM #SourceApprovers sourceApprover
    INNER JOIN #IdentityUsers identityUser ON identityUser.IdentityKey = sourceApprover.IdentityKey
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.FMS_ApproverDepartments existingAssignment
        WHERE existingAssignment.UserID = identityUser.KeeperUserID
          AND existingAssignment.DepartmentCode = sourceApprover.DepartmentCode
    );

    UPDATE assignment
    SET DepartmentGroup = sourceGroup.DepartmentGroup
    FROM dbo.FMS_ApproverDepartments assignment
    INNER JOIN
    (
        SELECT identityUser.KeeperUserID AS UserID,
               sourceApprover.DepartmentCode,
               MAX(sourceApprover.DepartmentGroup) AS DepartmentGroup
        FROM #SourceApprovers sourceApprover
        INNER JOIN #IdentityUsers identityUser ON identityUser.IdentityKey = sourceApprover.IdentityKey
        GROUP BY identityUser.KeeperUserID, sourceApprover.DepartmentCode
    ) sourceGroup
        ON sourceGroup.UserID = assignment.UserID
       AND sourceGroup.DepartmentCode = assignment.DepartmentCode;

    DELETE duplicateUser
    FROM dbo.FMS_AppUsers duplicateUser
    INNER JOIN #UserMerge mergeRow ON mergeRow.UserID = duplicateUser.UserId
    WHERE mergeRow.UserID <> mergeRow.KeeperUserID;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.FMS_AppUsers
        GROUP BY DisplayName
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 51135, 'Duplicate display names remain after FineReport approver consolidation.', 1;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    ;THROW;
END CATCH
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
      AND name = N'UX_AppUsers_Email'
)
BEGIN
    CREATE UNIQUE INDEX UX_AppUsers_Email
        ON dbo.FMS_AppUsers(Email)
        WHERE Email IS NOT NULL;
END
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FMS_AppUsers')
      AND name = N'UX_AppUsers_DisplayName'
)
BEGIN
    CREATE UNIQUE INDEX UX_AppUsers_DisplayName
        ON dbo.FMS_AppUsers(DisplayName);
END
GO
