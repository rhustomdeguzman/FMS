USE [FMS];
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'VendorCode') IS NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ADD VendorCode varchar(50) NULL;
END;

IF COL_LENGTH(N'dbo.FMS_CashAdvanceRequests_Dtl', N'Vendor') IS NOT NULL
BEGIN
    ALTER TABLE dbo.FMS_CashAdvanceRequests_Dtl ALTER COLUMN Vendor nvarchar(200) NULL;
END;

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.sp_OtherBusinessPartners_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT LTRIM(RTRIM(BP_Code)) AS BP_Code,
           LTRIM(RTRIM(BP_Name)) AS BP_Name
    FROM dbo.FMS_OtherBP_CLI
    WHERE NULLIF(LTRIM(RTRIM(BP_Code)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(BP_Name)), N'') IS NOT NULL
    ORDER BY LTRIM(RTRIM(BP_Name));
END
GO
