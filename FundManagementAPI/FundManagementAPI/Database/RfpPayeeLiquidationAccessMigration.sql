USE [FMS];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Resolve only a unique active user. Ignore punctuation and whitespace used
-- in personal names, but never choose arbitrarily between duplicate names.
CREATE OR ALTER FUNCTION dbo.fn_CashAdvancePayeeUserId(@RequestId int)
RETURNS int
AS
BEGIN
    DECLARE @UserId int;
    SELECT @UserId = MIN(u.UserId)
    FROM dbo.FMS_CashAdvanceRequests r
    INNER JOIN FineReport.dbo.New_ORFP_Hdr h
        ON CONVERT(nvarchar(50), h.RF_Number) COLLATE DATABASE_DEFAULT = r.RfpRequestNumber
       AND (r.CompanyID IS NULL OR h.CompanyID = r.CompanyID)
    INNER JOIN dbo.FMS_AppUsers u
        ON UPPER(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(u.DisplayName)), N',', N''), N'.', N''), N' ', N''))
         = UPPER(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(h.PayeeName COLLATE DATABASE_DEFAULT)), N',', N''), N'.', N''), N' ', N''))
    WHERE r.CashAdvanceRequestId = @RequestId
      AND r.OriginalCashAdvanceRequestId IS NULL
      AND COALESCE(r.RequestType, N'cash_advance') = N'cash_advance'
      AND u.IsActive = 1
      AND NULLIF(LTRIM(RTRIM(h.PayeeName)), N'') IS NOT NULL
    HAVING COUNT(DISTINCT u.UserId) = 1
       AND (SELECT COUNT(DISTINCT sourceHeader.CompanyID)
            FROM FineReport.dbo.New_ORFP_Hdr sourceHeader
            WHERE CONVERT(nvarchar(50), sourceHeader.RF_Number) COLLATE DATABASE_DEFAULT
                = (SELECT RfpRequestNumber FROM dbo.FMS_CashAdvanceRequests WHERE CashAdvanceRequestId = @RequestId)
              AND ((SELECT CompanyID FROM dbo.FMS_CashAdvanceRequests WHERE CashAdvanceRequestId = @RequestId) IS NULL
                   OR sourceHeader.CompanyID = (SELECT CompanyID FROM dbo.FMS_CashAdvanceRequests WHERE CashAdvanceRequestId = @RequestId))) = 1;
    RETURN @UserId;
END;
GO

-- Patch the installed procedures so existing workflow customizations survive.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @Definition nvarchar(max), @Original nvarchar(max), @Position int;
SET @Definition = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_GetForUser'));
IF @Definition IS NULL
    THROW 51200, 'GetForUser procedure is missing.', 1;
IF @Definition NOT LIKE N'%AS PayeeUserId%'
BEGIN
    SET @Original = @Definition;
    SET @Definition = REPLACE(@Definition, N'SELECT r.CashAdvanceRequestId,',
        N'SELECT dbo.fn_CashAdvancePayeeUserId(r.CashAdvanceRequestId) AS PayeeUserId, r.CashAdvanceRequestId,');
    IF @Definition = @Original
        THROW 51201, 'GetForUser select anchor was not found.', 1;
    SET @Original = @Definition;
    SET @Definition = REPLACE(@Definition,
        N'(@Role = ''requestor'' AND',
        N'dbo.fn_CashAdvancePayeeUserId(r.CashAdvanceRequestId) = @UserId OR (@Role = ''requestor'' AND');
    IF @Definition = @Original
        THROW 51202, 'GetForUser access anchor was not found.', 1;
    SET @Position = CHARINDEX(N'PROCEDURE', UPPER(@Definition));
    IF @Position = 0 THROW 51203, 'Invalid GetForUser definition.', 1;
    SET @Definition = STUFF(@Definition, 1, @Position - 1, N'ALTER ');
    EXEC sys.sp_executesql @Definition;
END;

SET @Definition = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_CashAdvanceRequests_SubmitLiquidation'));
IF @Definition IS NULL THROW 51204, 'SubmitLiquidation procedure is missing.', 1;
IF @Definition NOT LIKE N'%fn_CashAdvancePayeeUserId%'
BEGIN
    SET @Original = @Definition;
    SET @Definition = REPLACE(@Definition,
        N'IF @LiquidatingUserId IS NOT NULL AND @LiquidatingUserId <> @CurrentOwnerUserId',
        N'IF @LiquidatingUserId IS NOT NULL
       AND @LiquidatingUserId = dbo.fn_CashAdvancePayeeUserId(@CashAdvanceRequestId)
       AND @LiquidatingUserId <> @CurrentOwnerUserId
    BEGIN
        SET @ShouldClaimFullCustody = 1;
    END
    ELSE IF @LiquidatingUserId IS NOT NULL AND @LiquidatingUserId <> @CurrentOwnerUserId');
    IF @Definition = @Original THROW 51205, 'SubmitLiquidation access anchor was not found.', 1;
    SET @Position = CHARINDEX(N'PROCEDURE', UPPER(@Definition));
    IF @Position = 0 THROW 51206, 'Invalid SubmitLiquidation definition.', 1;
    SET @Definition = STUFF(@Definition, 1, @Position - 1, N'ALTER ');
    EXEC sys.sp_executesql @Definition;
END;
COMMIT;
GO

-- Expected PayeeUserId for RFP 53963: 122, provided its name matches uniquely.
SELECT r.RequestNumber, r.RfpRequestNumber,
       dbo.fn_CashAdvancePayeeUserId(r.CashAdvanceRequestId) AS PayeeUserId
FROM dbo.FMS_CashAdvanceRequests r
WHERE r.RfpRequestNumber = N'53963';
GO
