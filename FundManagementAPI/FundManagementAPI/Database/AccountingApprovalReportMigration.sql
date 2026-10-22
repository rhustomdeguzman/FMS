CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_GetAccountingReport
    @UserId int,
    @FromDate datetime = NULL,
    @ToDate datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RequestNumber,
           COALESCE(NULLIF(LTRIM(RTRIM(d.VendorCode)), ''), N'') AS VendorCode,
           COALESCE(d.[Description], N'') AS [Description],
           COALESCE(NULLIF(LTRIM(RTRIM(d.ProjectCode)), N''), N'') AS ProjectCode,
           COALESCE(d.ProfitCenterCode, N'') AS ProfitCenterCode,
           d.Amount,
           COALESCE(d.InvoiceRef, N'') AS InvoiceRef,
           COALESCE(NULLIF(LTRIM(RTRIM(d.ExpenseTypeCode)), ''), N'') AS ExpenseTypeCode
    FROM dbo.FMS_CashAdvanceRequests_Dtl d
    INNER JOIN dbo.FMS_CashAdvanceRequests r ON r.CashAdvanceRequestId = d.CashAdvanceRequestId
    WHERE EXISTS
    (
        SELECT 1
        FROM dbo.FMS_CashAdvanceHistory accountingHistory
        WHERE accountingHistory.CashAdvanceRequestId = d.CashAdvanceRequestId
          AND accountingHistory.ActorUserId = @UserId
          AND accountingHistory.Action IN ('approved_by_accounting', 'returned')
          AND (@FromDate IS NULL OR accountingHistory.AuditDate >= @FromDate)
          AND (@ToDate IS NULL OR accountingHistory.AuditDate < DATEADD(DAY, 1, CONVERT(date, @ToDate)))
    )
    ORDER BY r.RequestNumber, d.CashAdvanceRequestDtlId;
END
GO
