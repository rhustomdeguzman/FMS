SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'dbo.FMS_ApproverDepartments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FMS_Departments', N'U') IS NULL
BEGIN
    THROW 51140, 'Department assignment tables must exist before enabling department-based transfers.', 1;
END
GO

CREATE OR ALTER VIEW dbo.vw_FMS_AppUsers
AS
    SELECT userRow.UserId,
           userRow.Username,
           userRow.DisplayName,
           department.DepartmentName AS Department,
           roleRow.RoleKey AS Role,
           userRow.Title,
           userRow.PasswordHash,
           userRow.IsActive,
           userRow.AuditDate,
           userRow.UpdatedAt,
           userRow.PettyCashFundAmount,
           userRow.RoleCode,
           primaryDepartment.DepartmentCode,
           departmentGroups.DepartmentGroups
    FROM dbo.FMS_AppUsers userRow
    INNER JOIN dbo.FMS_Roles roleRow ON roleRow.RoleCode = userRow.RoleCode
    OUTER APPLY
    (
        SELECT MAX(assignment.DepartmentCode) AS DepartmentCode
        FROM dbo.FMS_ApproverDepartments assignment
        WHERE assignment.UserID = userRow.UserId
    ) primaryDepartment
    LEFT JOIN dbo.FMS_Departments department
        ON department.DepartmentCode = primaryDepartment.DepartmentCode
    OUTER APPLY
    (
        SELECT STRING_AGG(CONVERT(nvarchar(max), grouped.DepartmentGroup), N',')
                   WITHIN GROUP (ORDER BY grouped.DepartmentGroup) AS DepartmentGroups
        FROM
        (
            SELECT DISTINCT assignment.DepartmentGroup
            FROM dbo.FMS_ApproverDepartments assignment
            WHERE assignment.UserID = userRow.UserId
              AND assignment.DepartmentGroup IS NOT NULL
        ) grouped
    ) departmentGroups;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AppUsers_GetAll
    @IncludeInactive bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive,
           PettyCashFundAmount, RoleCode, DepartmentCode, DepartmentGroups
    FROM dbo.vw_FMS_AppUsers
    WHERE @IncludeInactive = 1 OR IsActive = 1
    ORDER BY RoleCode, Department, DisplayName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Auth_Login
    @Username nvarchar(50),
    @Password nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PasswordHash varbinary(32) = HASHBYTES('SHA2_256', CONVERT(varbinary(max), @Password));

    SELECT UserId, Username, DisplayName, Department, Role, Title, IsActive,
           PettyCashFundAmount, RoleCode, DepartmentCode, DepartmentGroups
    FROM dbo.vw_FMS_AppUsers
    WHERE Username = @Username
      AND PasswordHash = @PasswordHash
      AND IsActive = 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CashAdvanceRequests_Transfer
    @CashAdvanceRequestId int,
    @ToUserId int,
    @Amount decimal(19,4) = 0,
    @TransferWholeRequest bit = 0,
    @Notes nvarchar(1000) = NULL
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @StatusId int;
    DECLARE @RequestNumber nvarchar(50);
    DECLARE @RequestorUserId int;
    DECLARE @CurrentOwnerUserId int;
    DECLARE @CurrentOwnerName nvarchar(200);
    DECLARE @ToUserName nvarchar(200);
    DECLARE @ExistingPendingTransferToUserId int;
    DECLARE @AvailableAmount decimal(19,4);
    DECLARE @TransferAmount decimal(19,4);
    DECLARE @TransferIsWholeRequest bit;
    DECLARE @RequestDepartment nvarchar(200);

    SELECT @ToUserName = DisplayName
    FROM dbo.vw_FMS_AppUsers
    WHERE UserId = @ToUserId
      AND IsActive = 1
      AND Role = N'department_head';

    IF @ToUserName IS NULL
    BEGIN
        THROW 51002, 'Transfer target must be an active department approver.', 1;
    END

    BEGIN TRANSACTION;

    SELECT @StatusId = requestRow.StatusId,
           @RequestNumber = requestRow.RequestNumber,
           @RequestorUserId = requestRow.RequestorUserId,
           @CurrentOwnerUserId = COALESCE(requestRow.CurrentOwnerUserId, requestRow.RequestorUserId),
           @CurrentOwnerName = owner.DisplayName,
           @ExistingPendingTransferToUserId = requestRow.PendingTransferToUserId,
           @AvailableAmount = COALESCE(requestRow.RemainingAmount, requestRow.Amount),
           @RequestDepartment = requestRow.Department
    FROM dbo.FMS_CashAdvanceRequests requestRow WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.vw_FMS_AppUsers owner
        ON owner.UserId = COALESCE(requestRow.CurrentOwnerUserId, requestRow.RequestorUserId)
    WHERE requestRow.CashAdvanceRequestId = @CashAdvanceRequestId;

    IF @StatusId IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51003, 'Cash advance request was not found.', 1;
    END

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FMS_ApproverDepartments targetAssignment
        INNER JOIN dbo.FMS_Departments targetDepartment
            ON targetDepartment.DepartmentCode = targetAssignment.DepartmentCode
        WHERE targetAssignment.UserID = @ToUserId
          AND targetDepartment.IsActive = 1
          AND LTRIM(RTRIM(targetDepartment.DepartmentName)) = LTRIM(RTRIM(@RequestDepartment))
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51015, 'Transfer target must belong to the request department.', 1;
    END

    IF @StatusId NOT IN (0, 7)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51004, 'Only requests pending liquidation can be transferred.', 1;
    END

    IF @CurrentOwnerUserId = @ToUserId
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51006, 'Cash advance request is already assigned to the selected user.', 1;
    END

    IF @ExistingPendingTransferToUserId IS NOT NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51007, 'Cash advance request already has a pending transfer acknowledgement.', 1;
    END

    SET @TransferAmount = CASE WHEN @TransferWholeRequest = 1 THEN @AvailableAmount ELSE @Amount END;
    SET @TransferIsWholeRequest = CASE WHEN @TransferWholeRequest = 1 OR @TransferAmount = @AvailableAmount THEN 1 ELSE 0 END;

    IF @TransferAmount <= 0 OR @TransferAmount > @AvailableAmount
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51005, 'Transfer amount must be greater than zero and not exceed the remaining request amount.', 1;
    END

    UPDATE dbo.FMS_CashAdvanceRequests
    SET PendingTransferFromUserId = @CurrentOwnerUserId,
        PendingTransferToUserId = @ToUserId,
        PendingTransferAmount = @TransferAmount,
        PendingTransferIsWholeRequest = @TransferIsWholeRequest,
        PendingTransferNotes = @Notes,
        UpdatedAt = GETDATE()
    WHERE CashAdvanceRequestId = @CashAdvanceRequestId;

    INSERT INTO dbo.FMS_CashAdvanceTransfers
        (CashAdvanceRequestId, FromUserId, ToUserId, TransferAmount, IsWholeRequest, Status, Notes)
    VALUES
        (@CashAdvanceRequestId, @CurrentOwnerUserId, @ToUserId, @TransferAmount, @TransferIsWholeRequest, N'pending', @Notes);

    INSERT INTO dbo.FMS_CashAdvanceHistory (CashAdvanceRequestId, Action, ActorUserId, Amount, Notes)
    VALUES
    (
        @CashAdvanceRequestId, N'transfer_requested', @CurrentOwnerUserId, @TransferAmount,
        COALESCE(@Notes,
            CASE WHEN @TransferIsWholeRequest = 1
                 THEN CONCAT(N'Whole request transfer requested for ', @ToUserName, N'.')
                 ELSE CONCAT(N'Partial transfer requested for ', @ToUserName, N'.') END)
    );

    COMMIT TRANSACTION;
END
GO
