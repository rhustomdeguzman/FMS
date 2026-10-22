USE FMS;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RfpAttachments_GetMetadata
    @Id int,
    @Number nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET QUOTED_IDENTIFIER ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET XACT_ABORT ON;

    SELECT company.Name AS CompanyName, header.PayeeName,
           COALESCE(request.CurrentOwnerUserId, request.RequestorUserId) AS OwnerId, request.Department
    FROM dbo.FMS_CashAdvanceRequests request
    INNER JOIN FineReport.dbo.New_ORFP_Hdr header ON CONVERT(nvarchar(50), header.RF_Number) = @Number
    INNER JOIN dbo.vw_FMS_Company company ON company.ID = header.CompanyID
    WHERE request.CashAdvanceRequestId = @Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RfpAttachments_GetForRequest
    @Id int
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET QUOTED_IDENTIFIER ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET XACT_ABORT ON;

    SELECT AttachmentId, COALESCE(OriginalFileName, FileName) AS OriginalFileName, RelativePath, ContentType
    FROM dbo.FMS_CashAdvanceAttachments
    WHERE CashAdvanceRequestId = @Id AND REPLACE(RelativePath, '\', '/') LIKE 'liquidation/%'
    ORDER BY AttachmentId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RfpAttachments_Register
    @Folder varchar(500),
    @FileName varchar(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_NULLS ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET QUOTED_IDENTIFIER ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET XACT_ABORT ON;

    INSERT INTO FineReport.dbo.temporary_files (folder, filename, filetype, created_at, updated_at)
    VALUES (@Folder, @FileName, 'Requestor', GETDATE(), GETDATE());
END;
GO
