-- =============================================
-- Workload Profile Helper
-- =============================================
-- Quick and easy way to capture and save workload profiles
--
-- STEP 1: Run on PRODUCTION to capture profile
-- STEP 2: Copy the OUTPUT table result
-- STEP 3: Paste into Excel/Text file for safe keeping
-- STEP 4: Use the JSON output in generate_scaled_test_workload.sql
-- =============================================

SET NOCOUNT ON;

-- =============================================
-- OPTION A: SIMPLIFIED PROFILE CAPTURE (Easiest)
-- =============================================
-- This captures key metrics in an easy-to-copy table format

PRINT '========================================';
PRINT 'SIMPLIFIED WORKLOAD PROFILE';
PRINT '========================================';
PRINT 'Copy the table below and save it';
PRINT '========================================';
PRINT '';

-- Create temp table for easy export
IF OBJECT_ID('tempdb..#WorkloadProfile') IS NOT NULL
    DROP TABLE #WorkloadProfile;

CREATE TABLE #WorkloadProfile (
    [ProfileKey] VARCHAR(100),
    [ProfileValue] VARCHAR(500),
    [Category] VARCHAR(50),
    [Notes] VARCHAR(500)
);

-- System Configuration
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT 'CaptureDate', CONVERT(VARCHAR(30), GETUTCDATE(), 121), 'System', 'When this profile was captured';

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT 'ServerName', @@SERVERNAME, 'System', 'Source server name';

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT 'SQLVersion', CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)), 'System', 'SQL Server version';

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT 'Edition', CAST(SERVERPROPERTY('Edition') AS VARCHAR(100)), 'System', 'SQL Server edition';

-- CPU Configuration
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'LogicalCPUs',
    CAST([cpu_count] AS VARCHAR(10)),
    'CPU',
    'Total logical CPUs available'
FROM sys.dm_os_sys_info;

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'PhysicalCPUs',
    CAST([cpu_count] / [hyperthread_ratio] AS VARCHAR(10)),
    'CPU',
    'Physical CPU cores'
FROM sys.dm_os_sys_info;

-- Memory Configuration
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'TotalMemoryMB',
    CAST([total_physical_memory_kb] / 1024 AS VARCHAR(20)),
    'Memory',
    'Total physical memory in MB'
FROM sys.dm_os_sys_memory;

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'SQLServerMemoryMB',
    CAST(SUM([pages_kb]) / 1024 AS VARCHAR(20)),
    'Memory',
    'SQL Server buffer pool size in MB'
FROM sys.dm_os_memory_clerks
WHERE [type] = 'MEMORYCLERK_SQLBUFFERPOOL';

-- Read/Write Ratio
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'ReadPercentage',
    CAST(CAST(SUM([num_of_reads]) * 100.0 / NULLIF(SUM([num_of_reads]) + SUM([num_of_writes]), 0) AS DECIMAL(5,2)) AS VARCHAR(10)),
    'IO',
    'Percentage of IO operations that are reads'
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'WritePercentage',
    CAST(CAST(SUM([num_of_writes]) * 100.0 / NULLIF(SUM([num_of_reads]) + SUM([num_of_writes]), 0) AS DECIMAL(5,2)) AS VARCHAR(10)),
    'IO',
    'Percentage of IO operations that are writes'
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'TotalReadsMB',
    CAST(SUM([num_of_bytes_read]) / 1024 / 1024 AS VARCHAR(20)),
    'IO',
    'Total reads in MB since SQL Server started'
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'TotalWritesMB',
    CAST(SUM([num_of_bytes_written]) / 1024 / 1024 AS VARCHAR(20)),
    'IO',
    'Total writes in MB since SQL Server started'
FROM sys.dm_io_virtual_file_stats(NULL, NULL);

-- Top Wait Types (Top 5)
WITH [Waits] AS
(
    SELECT
        [wait_type],
        100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT',
        N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE', N'CXCONSUMER',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
        N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
        N'PREEMPTIVE_XE_GETTARGETSTATE', N'PVS_PREALLOCATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE',
        N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED',
        N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP',
        N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'VDI_CLIENT_OTHER', N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
        N'WAIT_XTP_RECOVERY', N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
    AND [waiting_tasks_count] > 0
)
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'WaitType' + CAST([RowNum] AS VARCHAR(2)),
    [wait_type],
    'WaitStats',
    'Top ' + CAST([RowNum] AS VARCHAR(2)) + ' wait type'
FROM [Waits]
WHERE [RowNum] <= 5;

WITH [Waits] AS
(
    SELECT
        [wait_type],
        100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT',
        N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE', N'CXCONSUMER',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
        N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
        N'PREEMPTIVE_XE_GETTARGETSTATE', N'PVS_PREALLOCATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE',
        N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED',
        N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP',
        N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'VDI_CLIENT_OTHER', N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
        N'WAIT_XTP_RECOVERY', N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
    AND [waiting_tasks_count] > 0
)
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'WaitType' + CAST([RowNum] AS VARCHAR(2)) + 'Percentage',
    CAST(CAST([Percentage] AS DECIMAL(5,2)) AS VARCHAR(10)),
    'WaitStats',
    'Percentage for top ' + CAST([RowNum] AS VARCHAR(2)) + ' wait type'
FROM [Waits]
WHERE [RowNum] <= 5;

-- Workload Type Classification
WITH [WaitAnalysis] AS
(
    SELECT
        [wait_type],
        100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() AS [Percentage]
    FROM sys.dm_os_wait_stats
    WHERE [waiting_tasks_count] > 0
)
INSERT INTO #WorkloadProfile ([ProfileKey], [ProfileValue], [Category], [Notes])
SELECT
    'WorkloadType',
    CASE
        WHEN EXISTS (SELECT 1 FROM [WaitAnalysis] WHERE [wait_type] LIKE 'PAGEIOLATCH%' AND [Percentage] > 20) THEN 'IO_INTENSIVE'
        WHEN EXISTS (SELECT 1 FROM [WaitAnalysis] WHERE [wait_type] = 'SOS_SCHEDULER_YIELD' AND [Percentage] > 30) THEN 'CPU_INTENSIVE'
        WHEN EXISTS (SELECT 1 FROM [WaitAnalysis] WHERE [wait_type] LIKE 'LCK_%' AND [Percentage] > 15) THEN 'BLOCKING_HEAVY'
        WHEN EXISTS (SELECT 1 FROM [WaitAnalysis] WHERE [wait_type] = 'WRITELOG' AND [Percentage] > 20) THEN 'WRITE_INTENSIVE'
        ELSE 'MIXED_WORKLOAD'
    END,
    'Workload',
    'Primary workload characteristic based on wait stats';

-- Display the profile
SELECT
    [Category],
    [ProfileKey],
    [ProfileValue],
    [Notes]
FROM #WorkloadProfile
ORDER BY
    CASE [Category]
        WHEN 'System' THEN 1
        WHEN 'CPU' THEN 2
        WHEN 'Memory' THEN 3
        WHEN 'IO' THEN 4
        WHEN 'WaitStats' THEN 5
        WHEN 'Workload' THEN 6
        ELSE 99
    END,
    [ProfileKey];

PRINT '';
PRINT '========================================';
PRINT 'EXPORT INSTRUCTIONS:';
PRINT '========================================';
PRINT '1. Right-click on results grid';
PRINT '2. Select "Save Results As..."';
PRINT '3. Save as CSV or Excel file';
PRINT '4. Name it: workload_profile_' + CONVERT(VARCHAR(10), GETDATE(), 112) + '.csv';
PRINT '';
PRINT 'OR for faster copy/paste:';
PRINT '1. Click in results grid';
PRINT '2. Press Ctrl+A (select all)';
PRINT '3. Press Ctrl+C (copy)';
PRINT '4. Paste into Excel or text file';
PRINT '========================================';

-- =============================================
-- OPTION B: GENERATE INSERT STATEMENTS FOR TEST ENVIRONMENT
-- =============================================

PRINT '';
PRINT '';
PRINT '========================================';
PRINT 'COPY THESE INSERT STATEMENTS FOR TEST:';
PRINT '========================================';
PRINT '';

-- Generate INSERT statements that can be copied directly
SELECT
    'INSERT INTO @ProductionProfile ([ProfileKey], [ProfileValue]) VALUES (''' +
    [ProfileKey] + ''', ''' + [ProfileValue] + ''');' AS [InsertStatements]
FROM #WorkloadProfile
WHERE [Category] IN ('CPU', 'IO', 'WaitStats', 'Workload')
ORDER BY [ProfileKey];

PRINT '';
PRINT '========================================';
PRINT 'Copy the INSERT statements above';
PRINT 'Paste into generate_scaled_test_workload.sql';
PRINT 'Replace the example values';
PRINT '========================================';

-- Cleanup
DROP TABLE #WorkloadProfile;
