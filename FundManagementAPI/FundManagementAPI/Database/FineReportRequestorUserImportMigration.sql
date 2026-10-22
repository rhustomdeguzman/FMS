SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_ImportFineReportRequestors
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF OBJECT_ID(N'FineReport..Main_Users', N'U') IS NULL
       OR OBJECT_ID(N'FineReport..New_ORFP_Hdr', N'U') IS NULL
       OR OBJECT_ID(N'FineReport..FineReport_RFP_Requestor', N'U') IS NULL
       OR OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
       OR OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
    BEGIN
        THROW 51160, 'Required FineReport or FMS user tables were not found.', 1;
    END;

    DECLARE @InsertedUsers TABLE
    (
        UserID int NOT NULL PRIMARY KEY,
        Email nvarchar(320) COLLATE DATABASE_DEFAULT NOT NULL UNIQUE
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        CREATE TABLE #SourceUsers
        (
            Email nvarchar(320) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
            DisplayName nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
            Username nvarchar(100) COLLATE DATABASE_DEFAULT NOT NULL,
            Title nvarchar(100) COLLATE DATABASE_DEFAULT NOT NULL,
            EmployeeID nvarchar(50) COLLATE DATABASE_DEFAULT NULL
        );

        INSERT INTO #SourceUsers (Email, DisplayName, Username, Title, EmployeeID)
        SELECT LOWER(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceUser.email)))),
               CONVERT(nvarchar(200), LTRIM(RTRIM(sourceUser.name))),
               CONVERT(nvarchar(100), LOWER(LTRIM(RTRIM(sourceUser.email)))),
               CONVERT(nvarchar(100), COALESCE(
                   NULLIF(LTRIM(RTRIM(sourceUser.position)), N''),
                   requestorRole.DefaultTitle,
                   N'Requestor'
               )),
               CONVERT(nvarchar(50), sourceUser.employee_id)
        FROM FineReport..Main_Users sourceUser
        LEFT JOIN dbo.FMS_Roles requestorRole
            ON requestorRole.RoleCode = 2
        WHERE sourceUser.email IN
        (
            SELECT requestor.EmailAddress
            FROM FineReport..New_ORFP_Hdr sourceHeader
            INNER JOIN FineReport..FineReport_RFP_Requestor requestor
                ON sourceHeader.RequestorID = requestor.RequestorID
            WHERE sourceHeader.TypeOfExpense = N'3'
              AND sourceHeader.[Status] = N'1'
              AND sourceHeader.PurOfDisbursement NOT LIKE N'%Company Loan%'
        );

        IF EXISTS
        (
            SELECT 1
            FROM #SourceUsers
            WHERE NULLIF(Email, N'') IS NULL
               OR NULLIF(DisplayName, N'') IS NULL
        )
        BEGIN
            THROW 51161, 'A selected FineReport requestor has a blank email or name.', 1;
        END;

        INSERT INTO dbo.FMS_AppUsers
            (Username, DisplayName, Email, Title, RoleCode, PasswordHash, PettyCashFundAmount)
        OUTPUT inserted.UserId, inserted.Email
            INTO @InsertedUsers (UserID, Email)
        SELECT sourceUser.Username,
               CASE
                   WHEN EXISTS
                   (
                       SELECT 1
                       FROM dbo.FMS_AppUsers existingUser
                       WHERE existingUser.DisplayName = sourceUser.DisplayName
                   )
                   THEN CONVERT(nvarchar(200), CONCAT(sourceUser.DisplayName, N' (', COALESCE(sourceUser.EmployeeID, sourceUser.Email), N')'))
                   ELSE sourceUser.DisplayName
               END,
               sourceUser.Email,
               sourceUser.Title,
               2,
               HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'password123')),
               NULL
        FROM #SourceUsers sourceUser
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_AppUsers existingUser
            WHERE existingUser.Email = sourceUser.Email
        );

        INSERT INTO dbo.FMS_ApproverDepartments (UserID, DepartmentCode, DepartmentGroup)
        SELECT DISTINCT insertedUser.UserID,
               department.DepartmentCode,
               TRY_CONVERT(int, department.DepartmentGroup)
        FROM @InsertedUsers insertedUser
        INNER JOIN FineReport..FineReport_RFP_Requestor requestor
            ON LOWER(LTRIM(RTRIM(CONVERT(nvarchar(320), requestor.EmailAddress)))) = insertedUser.Email
        INNER JOIN FineReport..New_ORFP_Hdr sourceHeader
            ON sourceHeader.RequestorID = requestor.RequestorID
           AND sourceHeader.TypeOfExpense = N'3'
           AND sourceHeader.[Status] = N'1'
           AND sourceHeader.PurOfDisbursement NOT LIKE N'%Company Loan%'
        INNER JOIN dbo.FMS_Departments department
            ON department.DepartmentCode = TRY_CONVERT(int, sourceHeader.ReqGroup)
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FMS_ApproverDepartments existingAssignment
            WHERE existingAssignment.UserID = insertedUser.UserID
              AND existingAssignment.DepartmentCode = department.DepartmentCode
        );

        DECLARE @InsertedAssignments int = @@ROWCOUNT;

        -- Include existing FMS users as well as users created by this import.
        IF EXISTS
        (
            SELECT LOWER(LTRIM(RTRIM(Email)))
            FROM dbo.FMS_AppUsers
            WHERE NULLIF(LTRIM(RTRIM(Email)), N'') IS NOT NULL
            GROUP BY LOWER(LTRIM(RTRIM(Email)))
            HAVING COUNT(*) > 1
        )
            THROW 51162, 'Duplicate FMS user emails prevent a unique FineReport FMS_id mapping.', 1;

        UPDATE mainUser
        SET FMS_id = appUser.UserId
        FROM FineReport..Main_Users mainUser
        INNER JOIN dbo.FMS_AppUsers appUser
            ON LOWER(LTRIM(RTRIM(CONVERT(nvarchar(320), mainUser.email)))) COLLATE DATABASE_DEFAULT
             = LOWER(LTRIM(RTRIM(appUser.Email)))
        WHERE NULLIF(LTRIM(RTRIM(appUser.Email)), N'') IS NOT NULL
          AND (mainUser.FMS_id IS NULL OR mainUser.FMS_id <> appUser.UserId);

        COMMIT TRANSACTION;

        SELECT (SELECT COUNT(*) FROM #SourceUsers) AS SelectedUsers,
               (SELECT COUNT(*) FROM @InsertedUsers) AS InsertedUsers,
               (SELECT COUNT(*) FROM #SourceUsers) - (SELECT COUNT(*) FROM @InsertedUsers) AS SkippedExistingEmails,
               @InsertedAssignments AS InsertedDepartmentAssignments;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ;THROW;
    END CATCH;
END
GO
