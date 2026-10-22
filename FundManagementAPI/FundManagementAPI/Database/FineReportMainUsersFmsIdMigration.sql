-- Run in the FMS database. Only existing Main_Users rows matched by email are updated.
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FMS_AppUsers', N'U') IS NULL
   OR OBJECT_ID(N'FineReport..Main_Users', N'U') IS NULL
    THROW 51163, 'Required FMS or FineReport user table was not found.', 1;

IF COL_LENGTH(N'FineReport..Main_Users', N'FMS_id') IS NULL
    THROW 51164, 'FineReport..Main_Users.FMS_id must exist before running this migration.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

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

    DECLARE @UpdatedUsers int = @@ROWCOUNT;
    COMMIT TRANSACTION;
    SELECT @UpdatedUsers AS UpdatedFineReportUsers;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
