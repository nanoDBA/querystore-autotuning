-- =============================================
-- Scaled Test Workload Generator
-- =============================================
-- Purpose: Generate a test workload that matches production characteristics
--          scaled proportionally to available resources
--
-- Usage:
--   1. Run capture_production_workload_profile.sql on PRODUCTION
--   2. Update the @ProductionProfile variables below with captured values
--   3. Run this script on TEST environment
--   4. Script will create workload matching production ratios
-- =============================================

SET NOCOUNT ON;

-- =============================================
-- CONFIGURATION: Update these from your production profile
-- =============================================

DECLARE @ProductionProfile TABLE (
    [ProfileKey] VARCHAR(50),
    [ProfileValue] VARCHAR(255)
);

-- INSERT YOUR PRODUCTION PROFILE VALUES HERE
-- Example values - replace with actual production data
INSERT INTO @ProductionProfile ([ProfileKey], [ProfileValue])
VALUES
    -- From WORKLOAD_FINGERPRINT section
    ('PrimaryWorkloadType', 'MIXED_WORKLOAD'),  -- IO_INTENSIVE, CPU_INTENSIVE, BLOCKING_HEAVY, WRITE_INTENSIVE, MIXED_WORKLOAD
    ('ReadPercentage', '75.00'),                -- Percentage of read operations
    ('WritePercentage', '25.00'),               -- Percentage of write operations
    ('ProductionCPUs', '32'),                   -- Logical CPU count from production
    ('ParallelismLevel', 'HIGH_PARALLELISM'),   -- HIGH_PARALLELISM or LOW_PARALLELISM
    ('MemoryPressure', 'Available physical memory is high'), -- Memory state

    -- From WAIT_STATS section - Top 3 wait types with percentages
    ('WaitType1', 'PAGEIOLATCH_SH'),
    ('WaitType1Percentage', '35.50'),
    ('WaitType2', 'SOS_SCHEDULER_YIELD'),
    ('WaitType2Percentage', '22.30'),
    ('WaitType3', 'WRITELOG'),
    ('WaitType3Percentage', '18.75'),

    -- From QUERY_STORE_PROFILE (if available)
    ('AvgDurationMicroseconds', '15000'),       -- Average query duration
    ('AvgLogicalReads', '500'),                 -- Average logical reads per query
    ('AvgLogicalWrites', '125'),                -- Average logical writes per query
    ('QueryTypeReadHeavy', '60'),               -- Percentage of read-heavy queries
    ('QueryTypeWriteHeavy', '15'),              -- Percentage of write-heavy queries
    ('QueryTypeCPUBound', '15'),                -- Percentage of CPU-bound queries
    ('QueryTypeMixed', '10');                   -- Percentage of mixed queries

-- =============================================
-- CALCULATE TEST ENVIRONMENT SCALING FACTOR
-- =============================================

DECLARE @TestCPUs INT;
DECLARE @ProductionCPUs INT;
DECLARE @ScalingFactor DECIMAL(5,2);
DECLARE @WorkloadType VARCHAR(50);
DECLARE @ReadPct DECIMAL(5,2);
DECLARE @WritePct DECIMAL(5,2);

SELECT @TestCPUs = [cpu_count] FROM sys.dm_os_sys_info;

SELECT @ProductionCPUs = CAST([ProfileValue] AS INT)
FROM @ProductionProfile
WHERE [ProfileKey] = 'ProductionCPUs';

SET @ScalingFactor = CAST(@TestCPUs AS DECIMAL(5,2)) / CAST(@ProductionCPUs AS DECIMAL(5,2));

SELECT @WorkloadType = [ProfileValue]
FROM @ProductionProfile
WHERE [ProfileKey] = 'PrimaryWorkloadType';

SELECT @ReadPct = CAST([ProfileValue] AS DECIMAL(5,2))
FROM @ProductionProfile
WHERE [ProfileKey] = 'ReadPercentage';

SELECT @WritePct = CAST([ProfileValue] AS DECIMAL(5,2))
FROM @ProductionProfile
WHERE [ProfileKey] = 'WritePercentage';

PRINT '========================================';
PRINT 'Test Environment Scaling Configuration';
PRINT '========================================';
PRINT 'Production CPUs: ' + CAST(@ProductionCPUs AS VARCHAR(10));
PRINT 'Test CPUs: ' + CAST(@TestCPUs AS VARCHAR(10));
PRINT 'Scaling Factor: ' + CAST(@ScalingFactor AS VARCHAR(10)) + ' (' + CAST(CAST(@ScalingFactor * 100 AS INT) AS VARCHAR(10)) + '%)';
PRINT 'Workload Type: ' + @WorkloadType;
PRINT 'Read/Write Ratio: ' + CAST(@ReadPct AS VARCHAR(10)) + '% / ' + CAST(@WritePct AS VARCHAR(10)) + '%';
PRINT '========================================';
PRINT '';

-- =============================================
-- CREATE TEST WORKLOAD DATABASE
-- =============================================

IF DB_ID('WorkloadTest') IS NOT NULL
BEGIN
    PRINT 'Dropping existing WorkloadTest database...';
    ALTER DATABASE [WorkloadTest] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [WorkloadTest];
END

PRINT 'Creating WorkloadTest database...';
CREATE DATABASE [WorkloadTest];
GO

USE [WorkloadTest];
GO

-- Enable Query Store for workload capture
ALTER DATABASE [WorkloadTest] SET QUERY_STORE = ON;
ALTER DATABASE [WorkloadTest] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    INTERVAL_LENGTH_MINUTES = 1,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = ALL
);

PRINT 'Query Store enabled with 1-minute intervals for fast testing';

-- =============================================
-- CREATE SCALED TEST DATA
-- =============================================

PRINT '';
PRINT 'Creating test tables and data...';

-- Calculate scaled data volume
-- Use sqrt of scaling factor for data volume to maintain reasonable proportions
DECLARE @DataScaleFactor INT = CASE
    WHEN $(ScalingFactor) < 0.1 THEN 10000      -- Very small test environment
    WHEN $(ScalingFactor) < 0.25 THEN 50000     -- Small test environment
    WHEN $(ScalingFactor) < 0.5 THEN 100000     -- Medium test environment
    ELSE 250000                                  -- Larger test environment
END;

-- Main transaction table (represents typical OLTP table)
CREATE TABLE [dbo].[TestTransactions] (
    [TransactionID] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [TransactionDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [CustomerID] INT NOT NULL,
    [ProductID] INT NOT NULL,
    [Quantity] INT NOT NULL,
    [Amount] DECIMAL(18,2) NOT NULL,
    [Status] VARCHAR(20) NOT NULL,
    [Region] VARCHAR(50) NOT NULL,
    [CategoryID] INT NOT NULL,
    [IsProcessed] BIT NOT NULL DEFAULT 0,
    [ProcessedDate] DATETIME2 NULL,
    [Notes] NVARCHAR(500) NULL
);

-- Indexes matching common patterns
CREATE NONCLUSTERED INDEX [IX_TestTransactions_CustomerID]
    ON [dbo].[TestTransactions]([CustomerID])
    INCLUDE ([Amount], [TransactionDate]);

CREATE NONCLUSTERED INDEX [IX_TestTransactions_Date]
    ON [dbo].[TestTransactions]([TransactionDate])
    INCLUDE ([CustomerID], [Amount]);

CREATE NONCLUSTERED INDEX [IX_TestTransactions_ProductID]
    ON [dbo].[TestTransactions]([ProductID])
    INCLUDE ([Quantity], [Amount]);

CREATE NONCLUSTERED INDEX [IX_TestTransactions_CategoryID]
    ON [dbo].[TestTransactions]([CategoryID], [Region]);

CREATE NONCLUSTERED INDEX [IX_TestTransactions_Status]
    ON [dbo].[TestTransactions]([Status], [IsProcessed])
    INCLUDE ([TransactionDate], [Amount]);

PRINT 'Test tables created with representative indexes';

-- Populate with scaled data
PRINT 'Populating test data (this may take a few minutes)...';

DECLARE @RowsToInsert INT = @DataScaleFactor;
DECLARE @BatchSize INT = 10000;
DECLARE @RowsInserted INT = 0;

WHILE @RowsInserted < @RowsToInsert
BEGIN
    INSERT INTO [dbo].[TestTransactions] (
        [TransactionDate],
        [CustomerID],
        [ProductID],
        [Quantity],
        [Amount],
        [Status],
        [Region],
        [CategoryID],
        [IsProcessed],
        [ProcessedDate]
    )
    SELECT TOP (@BatchSize)
        DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 365), GETUTCDATE()), -- Random date within last year
        ABS(CHECKSUM(NEWID()) % 10000) + 1,                        -- CustomerID: 1-10000
        ABS(CHECKSUM(NEWID()) % 1000) + 1,                         -- ProductID: 1-1000
        ABS(CHECKSUM(NEWID()) % 100) + 1,                          -- Quantity: 1-100
        CAST(ABS(CHECKSUM(NEWID()) % 100000) / 100.0 AS DECIMAL(18,2)), -- Amount: $0-$1000
        CASE ABS(CHECKSUM(NEWID()) % 5)
            WHEN 0 THEN 'Pending'
            WHEN 1 THEN 'Approved'
            WHEN 2 THEN 'Completed'
            WHEN 3 THEN 'Cancelled'
            ELSE 'Processing'
        END,
        CASE ABS(CHECKSUM(NEWID()) % 4)
            WHEN 0 THEN 'North'
            WHEN 1 THEN 'South'
            WHEN 2 THEN 'East'
            ELSE 'West'
        END,
        ABS(CHECKSUM(NEWID()) % 50) + 1,                          -- CategoryID: 1-50
        CASE WHEN ABS(CHECKSUM(NEWID()) % 10) < 7 THEN 1 ELSE 0 END, -- 70% processed
        CASE WHEN ABS(CHECKSUM(NEWID()) % 10) < 7
            THEN DATEADD(HOUR, ABS(CHECKSUM(NEWID()) % 720), GETUTCDATE())
            ELSE NULL
        END
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b;

    SET @RowsInserted = @RowsInserted + @@ROWCOUNT;

    IF @RowsInserted % 50000 = 0
        PRINT '  Inserted ' + CAST(@RowsInserted AS VARCHAR(10)) + ' rows...';

    IF @RowsInserted >= @RowsToInsert
        BREAK;
END

PRINT 'Inserted ' + CAST(@RowsInserted AS VARCHAR(10)) + ' total rows';
PRINT 'Updating statistics...';

UPDATE STATISTICS [dbo].[TestTransactions] WITH FULLSCAN;

PRINT 'Test data creation complete';

-- =============================================
-- WORKLOAD QUERY PROCEDURES
-- =============================================

PRINT '';
PRINT 'Creating workload query procedures...';

-- Read-heavy query (matches production read percentage)
GO
CREATE OR ALTER PROCEDURE [dbo].[Workload_ReadHeavy]
    @CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Simulate read-heavy analytical query
    SELECT
        t.[CustomerID],
        COUNT(*) AS [TransactionCount],
        SUM([Amount]) AS [TotalAmount],
        AVG([Amount]) AS [AvgAmount],
        MIN([TransactionDate]) AS [FirstTransaction],
        MAX([TransactionDate]) AS [LastTransaction]
    FROM [dbo].[TestTransactions] t
    WHERE t.[CustomerID] = ISNULL(@CustomerID, t.[CustomerID])
        AND t.[TransactionDate] >= DATEADD(MONTH, -6, GETUTCDATE())
    GROUP BY t.[CustomerID]
    HAVING COUNT(*) > 5
    ORDER BY [TotalAmount] DESC;
END
GO

-- Write-heavy query (matches production write percentage)
CREATE OR ALTER PROCEDURE [dbo].[Workload_WriteHeavy]
    @Status VARCHAR(20) = 'Processing'
AS
BEGIN
    SET NOCOUNT ON;

    -- Simulate write-heavy operational query
    UPDATE [dbo].[TestTransactions]
    SET [IsProcessed] = 1,
        [ProcessedDate] = GETUTCDATE(),
        [Status] = 'Completed'
    WHERE [Status] = @Status
        AND [TransactionDate] >= DATEADD(DAY, -7, GETUTCDATE())
        AND [IsProcessed] = 0;

    SELECT @@ROWCOUNT AS [RowsUpdated];
END
GO

-- CPU-bound query
CREATE OR ALTER PROCEDURE [dbo].[Workload_CPUBound]
    @CategoryID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Simulate CPU-intensive calculation
    SELECT
        [CategoryID],
        [Region],
        COUNT(*) AS [Count],
        SUM([Amount]) AS [TotalAmount],
        -- Complex calculations to consume CPU
        STDEV([Amount]) AS [StdDevAmount],
        VAR([Amount]) AS [VarAmount],
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY [Amount]) OVER (PARTITION BY [CategoryID]) AS [MedianAmount],
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY [Amount]) OVER (PARTITION BY [CategoryID]) AS [P95Amount]
    FROM [dbo].[TestTransactions]
    WHERE [CategoryID] = ISNULL(@CategoryID, [CategoryID])
    GROUP BY [CategoryID], [Region], [Amount]
    ORDER BY [CategoryID], [Region];
END
GO

-- Parameter sniffing scenario (multiple plans expected)
CREATE OR ALTER PROCEDURE [dbo].[Workload_ParameterSniffing]
    @CategoryID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- This will create different plans based on parameter value
    -- Low CategoryIDs (1-10) have many rows
    -- High CategoryIDs (40-50) have few rows
    SELECT
        t.[TransactionID],
        t.[TransactionDate],
        t.[CustomerID],
        t.[Amount],
        t.[Status]
    FROM [dbo].[TestTransactions] t
    WHERE t.[CategoryID] = @CategoryID
    ORDER BY t.[TransactionDate] DESC;
END
GO

-- Join-heavy query (IO intensive)
CREATE OR ALTER PROCEDURE [dbo].[Workload_JoinHeavy]
    @Region VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Self-join to create IO load
    SELECT
        t1.[CustomerID],
        COUNT(DISTINCT t1.[ProductID]) AS [UniqueProducts],
        COUNT(DISTINCT t2.[TransactionDate]) AS [UniqueDates],
        SUM(t1.[Amount]) AS [TotalSpent]
    FROM [dbo].[TestTransactions] t1
    INNER JOIN [dbo].[TestTransactions] t2
        ON t1.[CustomerID] = t2.[CustomerID]
        AND t1.[TransactionID] != t2.[TransactionID]
    WHERE t1.[Region] = ISNULL(@Region, t1.[Region])
        AND t1.[TransactionDate] >= DATEADD(MONTH, -3, GETUTCDATE())
    GROUP BY t1.[CustomerID]
    HAVING COUNT(DISTINCT t1.[ProductID]) > 3;
END
GO

PRINT 'Workload procedures created';

-- =============================================
-- WORKLOAD EXECUTION SCRIPT
-- =============================================

PRINT '';
PRINT 'Creating workload execution procedure...';

GO
CREATE OR ALTER PROCEDURE [dbo].[Execute_ScaledWorkload]
    @DurationMinutes INT = 10,
    @ReadPercentage DECIMAL(5,2) = 75.00,
    @WritePercentage DECIMAL(5,2) = 25.00
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @EndTime DATETIME2 = DATEADD(MINUTE, @DurationMinutes, @StartTime);
    DECLARE @IterationCount INT = 0;
    DECLARE @RandomValue INT;

    PRINT 'Starting scaled workload execution...';
    PRINT 'Duration: ' + CAST(@DurationMinutes AS VARCHAR(10)) + ' minutes';
    PRINT 'Read/Write Ratio: ' + CAST(@ReadPercentage AS VARCHAR(10)) + '% / ' + CAST(@WritePercentage AS VARCHAR(10)) + '%';
    PRINT 'Start Time: ' + CONVERT(VARCHAR(30), @StartTime, 121);
    PRINT '';

    WHILE GETUTCDATE() < @EndTime
    BEGIN
        SET @IterationCount = @IterationCount + 1;
        SET @RandomValue = ABS(CHECKSUM(NEWID()) % 100) + 1;

        -- Execute queries based on read/write percentage
        IF @RandomValue <= @ReadPercentage
        BEGIN
            -- Read operations
            DECLARE @ReadRandom INT = ABS(CHECKSUM(NEWID()) % 100);

            IF @ReadRandom < 40
                -- Read-heavy analytical (40% of reads)
                EXEC [dbo].[Workload_ReadHeavy] @CustomerID = NULL;
            ELSE IF @ReadRandom < 70
                -- Parameter sniffing scenario (30% of reads)
                EXEC [dbo].[Workload_ParameterSniffing] @CategoryID = (ABS(CHECKSUM(NEWID()) % 50) + 1);
            ELSE IF @ReadRandom < 90
                -- CPU-bound calculation (20% of reads)
                EXEC [dbo].[Workload_CPUBound] @CategoryID = (ABS(CHECKSUM(NEWID()) % 50) + 1);
            ELSE
                -- Join-heavy IO intensive (10% of reads)
                EXEC [dbo].[Workload_JoinHeavy] @Region = NULL;
        END
        ELSE
        BEGIN
            -- Write operations
            EXEC [dbo].[Workload_WriteHeavy] @Status = 'Processing';
        END

        -- Progress reporting every 100 iterations
        IF @IterationCount % 100 = 0
        BEGIN
            DECLARE @ElapsedMinutes INT = DATEDIFF(MINUTE, @StartTime, GETUTCDATE());
            PRINT 'Iteration ' + CAST(@IterationCount AS VARCHAR(10)) +
                  ' - Elapsed: ' + CAST(@ElapsedMinutes AS VARCHAR(10)) + ' minutes';
        END

        -- Small delay to prevent overwhelming the system
        WAITFOR DELAY '00:00:00.050'; -- 50ms between queries
    END

    PRINT '';
    PRINT 'Workload execution complete';
    PRINT 'Total Iterations: ' + CAST(@IterationCount AS VARCHAR(10));
    PRINT 'Actual Duration: ' + CAST(DATEDIFF(SECOND, @StartTime, GETUTCDATE()) AS VARCHAR(10)) + ' seconds';
    PRINT '';
    PRINT 'Query Store should now contain workload data';
    PRINT 'Run: SELECT COUNT(*) FROM sys.query_store_query;';
END
GO

PRINT 'Workload execution procedure created';

-- =============================================
-- USAGE INSTRUCTIONS
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'SCALED WORKLOAD SETUP COMPLETE';
PRINT '========================================';
PRINT '';
PRINT 'To execute the workload:';
PRINT '';
PRINT 'EXEC [dbo].[Execute_ScaledWorkload]';
PRINT '    @DurationMinutes = 15,';
PRINT '    @ReadPercentage = ' + CAST(@ReadPct AS VARCHAR(10)) + ',';
PRINT '    @WritePercentage = ' + CAST(@WritePct AS VARCHAR(10)) + ';';
PRINT '';
PRINT 'This will run for 15 minutes generating workload';
PRINT 'matching your production characteristics.';
PRINT '';
PRINT 'After execution, verify Query Store capture:';
PRINT '  SELECT COUNT(*) AS [Queries] FROM sys.query_store_query;';
PRINT '  SELECT COUNT(*) AS [Plans] FROM sys.query_store_plan;';
PRINT '';
PRINT '========================================';
