USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProjectCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ProjectCode nvarchar(20) NULL;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'Project') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN Project nvarchar(200) NULL;
END;

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Projects_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    WITH Projects AS
    (
        SELECT NULLIF(LTRIM(RTRIM(ProjCode COLLATE DATABASE_DEFAULT)), N'') AS ProjCode,
               NULLIF(LTRIM(RTRIM(ProjName COLLATE DATABASE_DEFAULT)), N'') AS ProjName
        FROM FineReport..vwProjects
    )
    SELECT ProjCode,
           MIN(ProjName) AS ProjName
    FROM Projects
    WHERE ProjCode IS NOT NULL
      AND ProjName IS NOT NULL
    GROUP BY ProjCode
    ORDER BY MIN(ProjName);
END
GO
