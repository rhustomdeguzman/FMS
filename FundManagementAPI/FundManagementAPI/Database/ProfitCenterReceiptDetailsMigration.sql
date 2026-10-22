USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProfitCenterCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD ProfitCenterCode nvarchar(8) NULL;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'ProfitCenter') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN ProfitCenter nvarchar(200) NULL;
END;

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProfitCenters_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    WITH ProfitCenters AS
    (
        SELECT NULLIF(LTRIM(RTRIM(OcrCode COLLATE DATABASE_DEFAULT)), N'') AS OcrCode,
               NULLIF(LTRIM(RTRIM(OcrName COLLATE DATABASE_DEFAULT)), N'') AS OcrName
        FROM FineReport..vwProfitCenters
        WHERE OcrCode COLLATE DATABASE_DEFAULT LIKE N'OD-DP%'
    )
    SELECT OcrCode,
           MIN(OcrName) AS OcrName
    FROM ProfitCenters
    WHERE OcrCode IS NOT NULL
      AND OcrName IS NOT NULL
    GROUP BY OcrCode
    ORDER BY OcrCode;
END
GO
