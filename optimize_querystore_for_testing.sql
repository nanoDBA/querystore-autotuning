USE QSTest;
GO

-- Optimize Query Store for comprehensive testing
PRINT 'Optimizing Query Store settings for testing...'

-- First, check current settings
SELECT 
    'Current Query Store Settings' as Info,
    desired_state_desc,
    actual_state_desc,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc,
    wait_stats_capture_mode_desc,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
GO

-- Optimize settings for aggressive capture during testing
ALTER DATABASE QSTest SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 60,           -- Flush data more frequently
    INTERVAL_LENGTH_MINUTES = 1,                -- Shorter intervals for faster testing
    MAX_STORAGE_SIZE_MB = 1000,                 -- Larger storage for extensive testing
    STALE_CAPTURE_POLICY_THRESHOLD = 1,         -- Capture after 1 hour instead of 24
    SIZE_BASED_CLEANUP_MODE = AUTO,             -- Automatic cleanup when needed
    QUERY_CAPTURE_MODE = AUTO,                  -- Capture relevant queries automatically
    WAIT_STATS_CAPTURE_MODE = ON                -- Capture wait statistics
);
GO

-- Verify new settings
SELECT 
    'Updated Query Store Settings' as Info,
    desired_state_desc,
    actual_state_desc, 
    query_capture_mode_desc,
    size_based_cleanup_mode_desc,
    wait_stats_capture_mode_desc,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
GO

-- Clear existing Query Store data for clean testing
PRINT 'Clearing Query Store for fresh testing...'
ALTER DATABASE QSTest SET QUERY_STORE CLEAR;
GO

-- Wait for settings to take effect
WAITFOR DELAY '00:00:05';
GO

PRINT 'Query Store optimization completed. Ready for comprehensive testing.'
GO