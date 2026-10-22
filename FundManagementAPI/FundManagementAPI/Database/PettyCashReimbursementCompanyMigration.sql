-- Run after DepartmentCustodianAssignmentMigration.sql, before deploying the API.
-- Preserve the installed petty cash workflow while adding the selected company.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DECLARE @Definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_PettyCashRequests_Create'));
IF @Definition IS NULL
    THROW 51200, 'Install the petty cash workflow before this migration.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.parameters
    WHERE object_id = OBJECT_ID(N'dbo.sp_PettyCashRequests_Create') AND name = N'@CompanyId'
)
BEGIN
    DECLARE @Parameter nvarchar(200) = N'@TransportationDetailsJson nvarchar(max) = NULL';
    DECLARE @Identity nvarchar(200) = N'DECLARE @CashAdvanceRequestId int = CONVERT(int, SCOPE_IDENTITY());';
    IF CHARINDEX(@Parameter, @Definition) = 0 OR CHARINDEX(@Identity, @Definition) = 0
        THROW 51201, 'Unrecognized petty cash procedure. Review the installed definition before migration.', 1;

    SET @Definition = REPLACE(@Definition, @Parameter, @Parameter + N', @CompanyId int = NULL');
    SET @Definition = REPLACE(@Definition, N'SET NOCOUNT ON;', N'SET NOCOUNT ON;
        IF LOWER(LTRIM(RTRIM(@RequestType))) = N''petty_cash'' AND @CompanyId IS NULL
            THROW 51202, ''Company is required for petty cash reimbursement.'', 1;
        IF @CompanyId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.vw_FMS_Company WHERE ID = @CompanyId)
            THROW 51203, ''Select a valid company.'', 1;');
    SET @Definition = REPLACE(@Definition, @Identity, @Identity + N'
        UPDATE dbo.FMS_CashAdvanceRequests SET CompanyID = @CompanyId
        WHERE CashAdvanceRequestId = @CashAdvanceRequestId;');
    -- SQL Server may retain multiple spaces between CREATE and PROCEDURE.
    DECLARE @ProcedurePosition int = CHARINDEX(N'PROCEDURE', UPPER(@Definition));
    IF @ProcedurePosition = 0
        THROW 51204, 'Unrecognized procedure declaration.', 1;
    SET @Definition = N'ALTER ' + SUBSTRING(@Definition, @ProcedurePosition, LEN(@Definition));
    EXEC sys.sp_executesql @Definition;
END;
GO
