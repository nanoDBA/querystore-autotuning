-- =============================================
-- Production Workload Profile Capture
-- =============================================
-- Purpose: Capture workload characteristics from production to replicate in test environments
-- Output: JSON-formatted results for easy copy/paste back to analysis
--
-- Usage:
--   1. Run this script on PRODUCTION system
--   2. Copy the JSON output from Results to Text mode
--   3. Save as workload_profile_YYYY-MM-DD.json
--   4. Provide to test environment setup scripts
-- =============================================

SET NOCOUNT ON;

-- =============================================
-- 1. WAIT STATISTICS PROFILE (Normalized by Percentage)
-- =============================================
PRINT '=== WAIT STATISTICS PROFILE ===';

WITH [Waits] AS
(
    SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        -- Filter out benign waits (same as Wait_Types.sql)
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
),
[WaitStats] AS
(
    SELECT
        [W1].[wait_type] AS [WaitType],
        CAST([W1].[WaitS] AS DECIMAL(16,2)) AS [Wait_S],
        CAST([W1].[ResourceS] AS DECIMAL(16,2)) AS [Resource_S],
        CAST([W1].[SignalS] AS DECIMAL(16,2)) AS [Signal_S],
        [W1].[WaitCount],
        CAST([W1].[Percentage] AS DECIMAL(5,2)) AS [Percentage],
        CAST(([W1].[WaitS] / [W1].[WaitCount]) AS DECIMAL(16,4)) AS [AvgWait_S],
        CAST(([W1].[ResourceS] / [W1].[WaitCount]) AS DECIMAL(16,4)) AS [AvgRes_S],
        CAST(([W1].[SignalS] / [W1].[WaitCount]) AS DECIMAL(16,4)) AS [AvgSig_S]
    FROM [Waits] AS [W1]
    INNER JOIN [Waits] AS [W2] ON [W2].[RowNum] <= [W1].[RowNum]
    GROUP BY [W1].[RowNum], [W1].[wait_type], [W1].[WaitS], [W1].[ResourceS],
             [W1].[SignalS], [W1].[WaitCount], [W1].[Percentage]
    HAVING SUM([W2].[Percentage]) - MAX([W1].[Percentage]) < 95
)
SELECT
    'WAIT_STATS' AS [ProfileCategory],
    (
        SELECT
            [WaitType],
            [Percentage],
            [Wait_S],
            [WaitCount],
            [AvgWait_S],
            CASE
                WHEN [WaitType] LIKE 'PAGEIOLATCH%' THEN 'IO_BOUND'
                WHEN [WaitType] LIKE 'CXPACKET%' THEN 'PARALLELISM'
                WHEN [WaitType] LIKE 'LCK_%' THEN 'BLOCKING'
                WHEN [WaitType] LIKE 'WRITELOG%' THEN 'WRITE_BOUND'
                WHEN [WaitType] LIKE 'SOS_SCHEDULER_YIELD%' THEN 'CPU_BOUND'
                ELSE 'OTHER'
            END AS [WaitCategory]
        FROM [WaitStats]
        ORDER BY [Percentage] DESC
        FOR JSON PATH
    ) AS [WaitStatsJSON];

-- =============================================
-- 2. READ vs WRITE WORKLOAD RATIO
-- =============================================
PRINT '';
PRINT '=== READ vs WRITE RATIO ===';

SELECT
    'READ_WRITE_RATIO' AS [ProfileCategory],
    (
        SELECT
            SUM(CASE WHEN [type_desc] = 'ROWS' THEN [reserved_page_count] * 8 / 1024 ELSE 0 END) AS [DataMB],
            SUM(CASE WHEN [type_desc] = 'LOG' THEN [reserved_page_count] * 8 / 1024 ELSE 0 END) AS [LogMB],
            (
                SELECT
                    SUM([num_of_reads]) AS [TotalReads],
                    SUM([num_of_writes]) AS [TotalWrites],
                    CAST(SUM([num_of_reads]) * 100.0 / NULLIF(SUM([num_of_reads]) + SUM([num_of_writes]), 0) AS DECIMAL(5,2)) AS [ReadPercentage],
                    CAST(SUM([num_of_writes]) * 100.0 / NULLIF(SUM([num_of_reads]) + SUM([num_of_writes]), 0) AS DECIMAL(5,2)) AS [WritePercentage],
                    SUM([num_of_bytes_read]) / 1024 / 1024 AS [TotalReadMB],
                    SUM([num_of_bytes_written]) / 1024 / 1024 AS [TotalWriteMB]
                FROM sys.dm_io_virtual_file_stats(NULL, NULL)
            ) AS [IOStats]
        FROM sys.dm_db_partition_stats ps
        INNER JOIN sys.allocation_units au ON ps.partition_id = au.container_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [ReadWriteJSON];

-- =============================================
-- 3. BLOCKING PROFILE (Current + Historical)
-- =============================================
PRINT '';
PRINT '=== BLOCKING PROFILE ===';

-- Current blocking
WITH [BlockingChain] AS
(
    SELECT
        [session_id],
        [blocking_session_id],
        [wait_type],
        [wait_time],
        [wait_resource],
        DB_NAME([database_id]) AS [database_name],
        [status],
        [cpu_time],
        [logical_reads],
        [reads],
        [writes]
    FROM sys.dm_exec_requests
    WHERE [blocking_session_id] > 0
)
SELECT
    'BLOCKING_PROFILE' AS [ProfileCategory],
    (
        SELECT
            COUNT(*) AS [CurrentBlockedSessions],
            AVG([wait_time]) AS [AvgBlockWaitMs],
            MAX([wait_time]) AS [MaxBlockWaitMs],
            (
                SELECT TOP 5
                    [wait_type],
                    COUNT(*) AS [BlockCount]
                FROM [BlockingChain]
                GROUP BY [wait_type]
                ORDER BY COUNT(*) DESC
                FOR JSON PATH
            ) AS [TopBlockingWaitTypes]
        FROM [BlockingChain]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [BlockingJSON];

-- =============================================
-- 4. CPU UTILIZATION PROFILE
-- =============================================
PRINT '';
PRINT '=== CPU UTILIZATION PROFILE ===';

SELECT
    'CPU_PROFILE' AS [ProfileCategory],
    (
        SELECT
            [cpu_count] AS [LogicalCPUs],
            [hyperthread_ratio] AS [HyperthreadRatio],
            [cpu_count] / [hyperthread_ratio] AS [PhysicalCPUs],
            [scheduler_count] AS [SchedulerCount],
            (
                SELECT
                    AVG([current_tasks_count]) AS [AvgTasksPerScheduler],
                    AVG([runnable_tasks_count]) AS [AvgRunnableTasksPerScheduler],
                    AVG([work_queue_count]) AS [AvgWorkQueuePerScheduler],
                    SUM([current_workers_count]) AS [TotalWorkers],
                    SUM([active_workers_count]) AS [ActiveWorkers]
                FROM sys.dm_os_schedulers
                WHERE [status] = 'VISIBLE ONLINE'
            ) AS [SchedulerStats]
        FROM sys.dm_os_sys_info
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [CPUJSON];

-- =============================================
-- 5. QUERY STORE WORKLOAD PROFILE (if enabled)
-- =============================================
PRINT '';
PRINT '=== QUERY STORE WORKLOAD PROFILE ===';

IF EXISTS (
    SELECT 1
    FROM sys.database_query_store_options
    WHERE [actual_state] IN (1, 2) -- READ_WRITE or READ_ONLY
)
BEGIN
    SELECT
        'QUERY_STORE_PROFILE' AS [ProfileCategory],
        (
            SELECT
                COUNT(DISTINCT [query_id]) AS [UniqueQueries],
                COUNT(DISTINCT [plan_id]) AS [UniquePlans],
                SUM([count_executions]) AS [TotalExecutions],
                AVG([avg_duration]) AS [AvgDurationMicroseconds],
                AVG([avg_cpu_time]) AS [AvgCPUMicroseconds],
                AVG([avg_logical_io_reads]) AS [AvgLogicalReads],
                AVG([avg_logical_io_writes]) AS [AvgLogicalWrites],
                AVG([avg_physical_io_reads]) AS [AvgPhysicalReads],
                SUM([avg_rowcount] * [count_executions]) / NULLIF(SUM([count_executions]), 0) AS [AvgRowsPerExecution],
                -- Query type distribution
                (
                    SELECT
                        CASE
                            WHEN [avg_logical_io_writes] > [avg_logical_io_reads] THEN 'WRITE_HEAVY'
                            WHEN [avg_logical_io_reads] > [avg_logical_io_writes] * 10 THEN 'READ_HEAVY'
                            WHEN [avg_cpu_time] > [avg_duration] * 0.8 THEN 'CPU_BOUND'
                            ELSE 'MIXED'
                        END AS [QueryType],
                        COUNT(*) AS [Count],
                        CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS [Percentage]
                    FROM sys.query_store_runtime_stats
                    GROUP BY
                        CASE
                            WHEN [avg_logical_io_writes] > [avg_logical_io_reads] THEN 'WRITE_HEAVY'
                            WHEN [avg_logical_io_reads] > [avg_logical_io_writes] * 10 THEN 'READ_HEAVY'
                            WHEN [avg_cpu_time] > [avg_duration] * 0.8 THEN 'CPU_BOUND'
                            ELSE 'MIXED'
                        END
                    FOR JSON PATH
                ) AS [QueryTypeDistribution]
            FROM sys.query_store_runtime_stats
            WHERE [last_execution_time] >= DATEADD(HOUR, -24, GETUTCDATE())
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [QueryStoreJSON];
END
ELSE
BEGIN
    SELECT
        'QUERY_STORE_PROFILE' AS [ProfileCategory],
        '{"Status": "Query Store not enabled"}' AS [QueryStoreJSON];
END

-- =============================================
-- 6. TRANSACTION LOG ACTIVITY
-- =============================================
PRINT '';
PRINT '=== TRANSACTION LOG ACTIVITY ===';

SELECT
    'TRANSACTION_LOG_PROFILE' AS [ProfileCategory],
    (
        SELECT
            [database_id],
            DB_NAME([database_id]) AS [DatabaseName],
            [log_bytes_used_since_startup] / 1024 / 1024 AS [LogUsedMB_SinceStartup],
            [log_bytes_used_since_startup] / NULLIF(DATEDIFF(SECOND, [sqlserver_start_time], GETUTCDATE()), 0) / 1024 / 1024 AS [LogMB_PerSecond],
            (
                SELECT
                    SUM([log_bytes]) / 1024 / 1024 AS [CurrentLogSizeMB],
                    SUM([log_bytes_used]) / 1024 / 1024 AS [CurrentLogUsedMB],
                    CAST(SUM([log_bytes_used]) * 100.0 / NULLIF(SUM([log_bytes]), 0) AS DECIMAL(5,2)) AS [LogUsedPercentage]
                FROM sys.dm_db_log_space_usage
                WHERE [database_id] = ls.[database_id]
            ) AS [CurrentLogStats]
        FROM sys.dm_db_log_stats(NULL) ls
        CROSS APPLY (SELECT [sqlserver_start_time] FROM sys.dm_os_sys_info) si
        WHERE DB_NAME([database_id]) NOT IN ('master', 'model', 'msdb', 'tempdb')
        FOR JSON PATH
    ) AS [TransactionLogJSON];

-- =============================================
-- 7. MEMORY USAGE PROFILE
-- =============================================
PRINT '';
PRINT '=== MEMORY USAGE PROFILE ===';

SELECT
    'MEMORY_PROFILE' AS [ProfileCategory],
    (
        SELECT
            [total_physical_memory_kb] / 1024 AS [TotalPhysicalMemoryMB],
            [available_physical_memory_kb] / 1024 AS [AvailablePhysicalMemoryMB],
            [total_page_file_kb] / 1024 AS [TotalPageFileMB],
            [available_page_file_kb] / 1024 AS [AvailablePageFileMB],
            [system_memory_state_desc] AS [MemoryState],
            (
                SELECT
                    SUM([pages_kb]) / 1024 AS [BufferPoolMB],
                    (
                        SELECT
                            [type] AS [MemoryClerkType],
                            SUM([pages_kb]) / 1024 AS [SizeMB]
                        FROM sys.dm_os_memory_clerks
                        WHERE [type] IN ('MEMORYCLERK_SQLBUFFERPOOL', 'CACHESTORE_SQLCP',
                                        'CACHESTORE_OBJCP', 'USERSTORE_TOKENPERM')
                        GROUP BY [type]
                        FOR JSON PATH
                    ) AS [TopMemoryClerks]
                FROM sys.dm_os_memory_clerks
                WHERE [type] = 'MEMORYCLERK_SQLBUFFERPOOL'
            ) AS [SQLServerMemory]
        FROM sys.dm_os_sys_memory
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [MemoryJSON];

-- =============================================
-- 8. WORKLOAD FINGERPRINT SUMMARY
-- =============================================
PRINT '';
PRINT '=== WORKLOAD FINGERPRINT SUMMARY ===';
PRINT 'This summary can be used to create proportional test workloads';

WITH [WorkloadCharacteristics] AS
(
    SELECT
        -- Wait-based workload type
        CASE
            WHEN EXISTS (
                SELECT 1 FROM sys.dm_os_wait_stats
                WHERE [wait_type] LIKE 'PAGEIOLATCH%'
                AND 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() > 20
            ) THEN 'IO_INTENSIVE'
            WHEN EXISTS (
                SELECT 1 FROM sys.dm_os_wait_stats
                WHERE [wait_type] = 'SOS_SCHEDULER_YIELD'
                AND 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() > 30
            ) THEN 'CPU_INTENSIVE'
            WHEN EXISTS (
                SELECT 1 FROM sys.dm_os_wait_stats
                WHERE [wait_type] LIKE 'LCK_%'
                AND 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() > 15
            ) THEN 'BLOCKING_HEAVY'
            WHEN EXISTS (
                SELECT 1 FROM sys.dm_os_wait_stats
                WHERE [wait_type] = 'WRITELOG'
                AND 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() > 20
            ) THEN 'WRITE_INTENSIVE'
            ELSE 'MIXED_WORKLOAD'
        END AS [PrimaryWorkloadType],

        -- Read/Write ratio
        (
            SELECT
                CAST(SUM([num_of_reads]) * 100.0 / NULLIF(SUM([num_of_reads]) + SUM([num_of_writes]), 0) AS DECIMAL(5,2))
            FROM sys.dm_io_virtual_file_stats(NULL, NULL)
        ) AS [ReadPercentage],

        -- CPU info
        (SELECT [cpu_count] FROM sys.dm_os_sys_info) AS [LogicalCPUs],

        -- Memory pressure indicator
        (
            SELECT [system_memory_state_desc]
            FROM sys.dm_os_sys_memory
        ) AS [MemoryPressure],

        -- Parallelism indicator
        CASE
            WHEN EXISTS (
                SELECT 1 FROM sys.dm_os_wait_stats
                WHERE [wait_type] IN ('CXPACKET', 'CXCONSUMER')
                AND 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() > 10
            ) THEN 'HIGH_PARALLELISM'
            ELSE 'LOW_PARALLELISM'
        END AS [ParallelismLevel]
)
SELECT
    'WORKLOAD_FINGERPRINT' AS [ProfileCategory],
    (
        SELECT
            [PrimaryWorkloadType],
            [ReadPercentage],
            100 - [ReadPercentage] AS [WritePercentage],
            [LogicalCPUs],
            [MemoryPressure],
            [ParallelismLevel],
            GETUTCDATE() AS [CaptureTimestamp],
            @@SERVERNAME AS [SourceServer],
            @@VERSION AS [SQLVersion]
        FROM [WorkloadCharacteristics]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [FingerprintJSON];

GO

-- =============================================
-- EASY EXPORT INSTRUCTIONS
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'EXPORT INSTRUCTIONS:';
PRINT '========================================';
PRINT '1. Switch to "Results to Text" mode (Ctrl+T)';
PRINT '2. Re-run this script';
PRINT '3. Copy all JSON output';
PRINT '4. Save as: workload_profile_' + CONVERT(VARCHAR(10), GETDATE(), 112) + '.json';
PRINT '5. Provide JSON file for test environment setup';
PRINT '';
PRINT 'Alternative: Use "Results to File" mode (Ctrl+Shift+F)';
PRINT '========================================';
