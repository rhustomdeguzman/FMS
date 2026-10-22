USE FMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.FMS_RfpAttachmentImports', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FMS_RfpAttachmentImports
    (
        ImportId int IDENTITY PRIMARY KEY,
        CashAdvanceRequestId int NOT NULL REFERENCES dbo.FMS_CashAdvanceRequests(CashAdvanceRequestId),
        SourceFileName nvarchar(260) NOT NULL,
        AttachmentId int NULL REFERENCES dbo.FMS_CashAdvanceAttachments(AttachmentId),
        LastAttemptAt datetime2 NULL,
        CONSTRAINT UQ_FMS_RfpAttachmentImports_Source UNIQUE (CashAdvanceRequestId, SourceFileName)
    );
END;
GO

-- Reconcile existing imports as well as requests newly inserted by the SQL Agent job.
-- Only source RFP requests qualify; RFPs created by FMS are excluded.
CREATE OR ALTER PROCEDURE dbo.sp_RfpAttachmentImports_GetPending
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO dbo.FMS_RfpAttachmentImports (CashAdvanceRequestId, SourceFileName)
        SELECT DISTINCT request.CashAdvanceRequestId, CONVERT(nvarchar(260), files.filename) COLLATE DATABASE_DEFAULT
        FROM dbo.FMS_CashAdvanceRequests request
        INNER JOIN FineReport..New_ORFP_Hdr header
            ON request.RfpRequestNumber = CONVERT(nvarchar(50), header.RF_Number) COLLATE DATABASE_DEFAULT
           AND request.RequestNumber = CONCAT(N'RFP-', header.RF_Number) COLLATE DATABASE_DEFAULT
        INNER JOIN FineReport..temporary_files files
            ON CONVERT(nvarchar(500), files.folder) COLLATE DATABASE_DEFAULT
             = CONVERT(nvarchar(500), header.Attachment_Folder) COLLATE DATABASE_DEFAULT
        WHERE NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(500), header.Attachment_Folder))), N'') IS NOT NULL
          AND LEN(files.filename) BETWEEN 1 AND 260
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.FMS_RfpAttachmentImports existing WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.CashAdvanceRequestId = request.CashAdvanceRequestId
                AND existing.SourceFileName = CONVERT(nvarchar(260), files.filename) COLLATE DATABASE_DEFAULT
          );

        ;WITH pending AS
        (
            SELECT TOP (100) * FROM dbo.FMS_RfpAttachmentImports WITH (UPDLOCK, READPAST)
            WHERE AttachmentId IS NULL
            ORDER BY LastAttemptAt, ImportId
        )
        UPDATE pending SET LastAttemptAt = SYSUTCDATETIME()
        OUTPUT inserted.ImportId, inserted.CashAdvanceRequestId, inserted.SourceFileName;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RfpAttachmentImports_Complete
    @ImportId int,
    @StoredFileName nvarchar(260),
    @RelativePath nvarchar(500),
    @ContentType nvarchar(100),
    @FileSizeBytes bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @RequestId int, @SourceFileName nvarchar(260), @AttachmentId int;
        SELECT @RequestId = CashAdvanceRequestId, @SourceFileName = SourceFileName, @AttachmentId = AttachmentId
        FROM dbo.FMS_RfpAttachmentImports WITH (UPDLOCK, HOLDLOCK)
        WHERE ImportId = @ImportId;
        IF @RequestId IS NULL THROW 51170, 'RFP attachment import was not found.', 1;
        IF @AttachmentId IS NULL
        BEGIN
            INSERT INTO dbo.FMS_CashAdvanceAttachments
                (CashAdvanceRequestId, FileName, OriginalFileName, StoredFileName, RelativePath, ContentType, FileSizeBytes)
            VALUES (@RequestId, @SourceFileName, @SourceFileName, @StoredFileName, @RelativePath, @ContentType, @FileSizeBytes);
            UPDATE dbo.FMS_RfpAttachmentImports SET AttachmentId = CONVERT(int, SCOPE_IDENTITY()) WHERE ImportId = @ImportId;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
