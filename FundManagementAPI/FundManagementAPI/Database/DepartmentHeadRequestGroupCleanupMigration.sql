SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH SourceApproverAssignments AS
    (
        SELECT DISTINCT
               LOWER(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(320), sourceApprover.Email))), N'')) AS Email,
               TRY_CONVERT(int, sourceApprover.ID) AS DepartmentCode
        FROM FineReport..FineReport_RFP_Approvers sourceApprover
        WHERE sourceApprover.RoleCode = N'H'
          AND sourceApprover.Active = N'1'
    )
    DELETE assignment
    FROM dbo.FMS_ApproverDepartments assignment
    INNER JOIN dbo.FMS_AppUsers appUser
        ON appUser.UserId = assignment.UserID
       AND appUser.RoleCode = 3
    LEFT JOIN SourceApproverAssignments sourceAssignment
        ON sourceAssignment.Email = appUser.Email
       AND sourceAssignment.DepartmentCode = assignment.DepartmentCode
    WHERE assignment.DepartmentGroup IS NOT NULL
      AND sourceAssignment.DepartmentCode IS NULL;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    ;THROW;
END CATCH
GO
