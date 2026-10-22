USE msdb
GO

DECLARE @JobName sysname = N'FMS - Import FineReport Cash Advance Requests';
DECLARE @ScheduleName sysname = N'FMS - FineReport Cash Advance Import - Every Minute';
DECLARE @LegacyScheduleName sysname = N'FMS - FineReport Cash Advance Import - Every 5 Minutes';
DECLARE @ScheduleId int;
DECLARE @JobId uniqueidentifier;

SELECT @JobId = job_id
FROM dbo.sysjobs
WHERE name = @JobName;

IF @JobId IS NULL
BEGIN
    EXEC dbo.sp_add_job
        @job_name = @JobName,
        @enabled = 1,
        @description = N'Imports new approved FineReport cash advance headers and details into FMS. Existing RF numbers are skipped.',
        @owner_login_name = N'misd-rcdg',
        @job_id = @JobId OUTPUT;
END
ELSE
BEGIN
    EXEC dbo.sp_update_job
        @job_id = @JobId,
        @enabled = 1,
        @description = N'Imports new approved FineReport cash advance headers and details into FMS. Existing RF numbers are skipped.';
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.sysjobsteps
    WHERE job_id = @JobId
      AND step_name = N'Import new FineReport cash advance requests'
)
BEGIN
    EXEC dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Import new FineReport cash advance requests',
        @subsystem = N'TSQL',
        @database_name = N'FMS',
        @command = N'EXEC dbo.sp_CashAdvanceRequests_GetRequest;',
        @retry_attempts = 3,
        @retry_interval = 1,
        @on_success_action = 1,
        @on_fail_action = 2;
END
ELSE
BEGIN
    DECLARE @StepId int;

    SELECT @StepId = step_id
    FROM dbo.sysjobsteps
    WHERE job_id = @JobId
      AND step_name = N'Import new FineReport cash advance requests';

    EXEC dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_id = @StepId,
        @database_name = N'FMS',
        @command = N'EXEC dbo.sp_CashAdvanceRequests_GetRequest;',
        @retry_attempts = 3,
        @retry_interval = 1,
        @on_success_action = 1,
        @on_fail_action = 2;
END;

-- Reuse the previous schedule so rerunning this script updates deployed jobs.
SELECT TOP (1) @ScheduleId = schedule.schedule_id
FROM dbo.sysjobschedules jobSchedule
INNER JOIN dbo.sysschedules schedule
    ON schedule.schedule_id = jobSchedule.schedule_id
WHERE jobSchedule.job_id = @JobId
  AND schedule.name IN (@ScheduleName, @LegacyScheduleName)
ORDER BY CASE WHEN schedule.name = @ScheduleName THEN 0 ELSE 1 END;

IF @ScheduleId IS NULL
BEGIN
    EXEC dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = @ScheduleName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 1,
        @active_start_time = 0;
END
ELSE
BEGIN
    EXEC dbo.sp_update_schedule
        @schedule_id = @ScheduleId,
        @new_name = @ScheduleName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 1,
        @active_start_time = 0;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.sysjobservers
    WHERE job_id = @JobId
)
BEGIN
    EXEC dbo.sp_add_jobserver
        @job_id = @JobId;
END;
GO
