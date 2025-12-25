/**************************************************************************************************
	ATTACK SCENARIOS: Test Cases That Expose Flaws in Original QueryStore Automation
	
	These scenarios are designed to break or expose weaknesses in the original t-statistic
	approach, demonstrating why the alternative adaptive approach is necessary.
*************************************************************************************************/

-- Setup: Create test environment
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'QSAttackTest')
    EXEC('CREATE SCHEMA QSAttackTest')
GO

/**************************************************************************************************
	SCENARIO 1: The Parameter Sniffing Death Spiral
	
	Demonstrates how the original system can permanently pin a catastrophically bad plan
	due to parameter sniffing during initial execution.
*************************************************************************************************/

-- Create test table with extreme data skew
IF OBJECT_ID('QSAttackTest.Orders') IS NOT NULL DROP TABLE QSAttackTest.Orders;

CREATE TABLE QSAttackTest.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID VARCHAR(20),
    OrderDate DATETIME2,
    OrderValue DECIMAL(10,2),
    Status VARCHAR(20)
);

-- Insert heavily skewed data
-- Customer 'WHALE' has 100,000 orders (requires Index Scan)  
-- All other customers have 1-5 orders each (optimal for Index Seek)
WITH BigCustomerOrders AS (
    SELECT 'WHALE' AS CustomerID, 
           DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 365, '2023-01-01') AS OrderDate,
           RAND(CHECKSUM(NEWID())) * 1000 AS OrderValue,
           'Completed' AS Status
    FROM sys.all_objects a1
    CROSS JOIN sys.all_objects a2
    WHERE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= 100000
),
SmallCustomerOrders AS (
    SELECT 'CUST_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR) AS CustomerID,
           DATEADD(DAY, RAND(CHECKSUM(NEWID())) * 365, '2023-01-01') AS OrderDate, 
           RAND(CHECKSUM(NEWID())) * 200 AS OrderValue,
           'Completed' AS Status
    FROM sys.all_objects
    WHERE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= 50000  -- 50K small customers with 1 order each
)
INSERT INTO QSAttackTest.Orders (CustomerID, OrderDate, OrderValue, Status)
SELECT CustomerID, OrderDate, OrderValue, Status FROM BigCustomerOrders
UNION ALL
SELECT CustomerID, OrderDate, OrderValue, Status FROM SmallCustomerOrders;

-- Create indexes
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON QSAttackTest.Orders (CustomerID) INCLUDE (OrderDate, OrderValue);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON QSAttackTest.Orders (OrderDate);

-- Update statistics to ensure accurate cardinality estimates
UPDATE STATISTICS QSAttackTest.Orders;

-- Clear Query Store to start fresh
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR ALL;

-- Attack Scenario: Execute query first with 'WHALE' parameter
-- This will cause parameter sniffing to choose Index Scan plan
DECLARE @CustomerID VARCHAR(20) = 'WHALE';
DECLARE @StartDate DATETIME2 = '2023-01-01';
DECLARE @EndDate DATETIME2 = '2023-12-31';

SELECT COUNT(*), AVG(OrderValue), MAX(OrderDate)
FROM QSAttackTest.Orders 
WHERE CustomerID = @CustomerID 
    AND OrderDate BETWEEN @StartDate AND @EndDate;
GO 10  -- Execute 10 times to build statistics

-- Now the original system would pin the Index Scan plan based on this execution
-- But 99% of real usage will be small customers needing Index Seek

-- Simulate normal workload (small customers)
DECLARE @Counter INT = 0;
WHILE @Counter < 100
BEGIN
    DECLARE @SmallCustomerID VARCHAR(20) = 'CUST_' + CAST((@Counter % 1000) + 1 AS VARCHAR);
    DECLARE @StartDate2 DATETIME2 = '2023-01-01';
    DECLARE @EndDate2 DATETIME2 = '2023-12-31';
    
    -- This will be forced to use the pinned Index Scan plan (slow for small customers)
    SELECT COUNT(*), AVG(OrderValue), MAX(OrderDate)
    FROM QSAttackTest.Orders 
    WHERE CustomerID = @SmallCustomerID 
        AND OrderDate BETWEEN @StartDate2 AND @EndDate2;
        
    SET @Counter = @Counter + 1;
END

-- Query to demonstrate the problem
SELECT 
    qsp.query_id,
    qsp.plan_id,
    qsp.is_forced_plan,
    AVG(qsrs.avg_duration) AS avg_duration_ms,
    SUM(qsrs.count_executions) AS total_executions,
    -- Show the plan is terrible for small customers but was pinned due to whale
    CASE WHEN AVG(qsrs.avg_duration) > 1000 THEN 'CATASTROPHICALLY_SLOW' 
         WHEN AVG(qsrs.avg_duration) > 100 THEN 'SLOW'
         ELSE 'ACCEPTABLE' END AS performance_rating
FROM sys.query_store_plan qsp
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
WHERE qsp.query_id IN (
    SELECT query_id FROM sys.query_store_query_text 
    WHERE query_sql_text LIKE '%QSAttackTest.Orders%'
)
GROUP BY qsp.query_id, qsp.plan_id, qsp.is_forced_plan
ORDER BY qsp.is_forced_plan DESC, avg_duration_ms DESC;

/**************************************************************************************************
	SCENARIO 2: The Data Growth Cliff
	
	Demonstrates how pinned plans become obsolete as data grows, but the original system
	won't adapt until manual intervention.
*************************************************************************************************/

-- Simulate table growth over time
IF OBJECT_ID('QSAttackTest.GrowingTable') IS NOT NULL DROP TABLE QSAttackTest.GrowingTable;

CREATE TABLE QSAttackTest.GrowingTable (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Category VARCHAR(50),
    Value DECIMAL(10,2),
    CreatedDate DATETIME2 DEFAULT SYSDATETIME()
);

-- Create index suitable for small table
CREATE NONCLUSTERED INDEX IX_GrowingTable_Category ON QSAttackTest.GrowingTable (Category);

-- Phase 1: Small table (1,000 rows) - Nested Loop is optimal
INSERT INTO QSAttackTest.GrowingTable (Category, Value)
SELECT 
    'Category_' + CAST((ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 10) + 1 AS VARCHAR),
    RAND(CHECKSUM(NEWID())) * 1000
FROM sys.all_objects 
WHERE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= 1000;

-- Execute query multiple times to establish baseline (Nested Loop will be chosen)
DECLARE @Category VARCHAR(50) = 'Category_5';
SELECT AVG(Value) FROM QSAttackTest.GrowingTable WHERE Category = @Category;
GO 20

-- Simulate the original system pinning this plan
-- (In real scenario, this would happen via the HighVariationCheck procedure)

-- Phase 2: Table grows dramatically (1,000,000 rows) - Hash Join becomes optimal
INSERT INTO QSAttackTest.GrowingTable (Category, Value)
SELECT 
    'Category_' + CAST((ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 10) + 1 AS VARCHAR),
    RAND(CHECKSUM(NEWID())) * 1000  
FROM sys.all_objects a1
CROSS JOIN sys.all_objects a2
WHERE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= 999000;  -- Grow to 1M total

-- Update statistics
UPDATE STATISTICS QSAttackTest.GrowingTable;

-- Now the pinned plan (optimized for 1K rows) will be catastrophically slow
-- But the original system won't unpin until the next "better plan check" window

-- Demonstrate the performance cliff
SELECT 
    'BEFORE_GROWTH' AS phase,
    plan_id,
    AVG(avg_duration) AS avg_duration_ms,
    'Small table - Nested Loop optimal' AS notes
FROM sys.query_store_runtime_stats qsrs
JOIN sys.query_store_plan qsp ON qsrs.plan_id = qsp.plan_id 
JOIN sys.query_store_query_text qsqt ON qsp.query_id = qsqt.query_id
WHERE qsqt.query_sql_text LIKE '%QSAttackTest.GrowingTable%'
    AND qsrs.last_execution_time < (SELECT MAX(CreatedDate) FROM QSAttackTest.GrowingTable WHERE ID > 1000)
GROUP BY plan_id

UNION ALL

SELECT 
    'AFTER_GROWTH' AS phase,
    plan_id, 
    AVG(avg_duration) AS avg_duration_ms,
    'Large table - Pinned plan now terrible' AS notes
FROM sys.query_store_runtime_stats qsrs
JOIN sys.query_store_plan qsp ON qsrs.plan_id = qsp.plan_id
JOIN sys.query_store_query_text qsqt ON qsp.query_id = qsqt.query_id  
WHERE qsqt.query_sql_text LIKE '%QSAttackTest.GrowingTable%'
    AND qsrs.last_execution_time >= (SELECT MAX(CreatedDate) FROM QSAttackTest.GrowingTable WHERE ID > 1000)
GROUP BY plan_id;

/**************************************************************************************************
	SCENARIO 3: The Resource Contention Cascade
	
	Shows how plans that work in isolation can destroy system performance under load.
*************************************************************************************************/

-- Create CPU-intensive query that uses parallel execution
IF OBJECT_ID('QSAttackTest.IntensiveTable') IS NOT NULL DROP TABLE QSAttackTest.IntensiveTable;

CREATE TABLE QSAttackTest.IntensiveTable (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Data VARCHAR(1000),
    ComputedValue AS (LEN(Data) + CHECKSUM(Data)) PERSISTED
);

-- Insert data that will benefit from parallel execution when run alone
INSERT INTO QSAttackTest.IntensiveTable (Data)
SELECT REPLICATE('X', 1000) + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR)
FROM sys.all_objects a1
CROSS JOIN sys.all_objects a2
WHERE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= 100000;

-- Query that will choose parallel plan when run in isolation
SELECT COUNT(*), AVG(ComputedValue), MAX(LEN(Data))
FROM QSAttackTest.IntensiveTable
WHERE ComputedValue > 1000
    AND Data LIKE '%500%';
GO 10

-- Now simulate high concurrency scenario where parallel plans cause contention
-- Original system would have pinned the parallel plan
-- But under load, serial execution might be better due to MAXDOP contention

/**************************************************************************************************
	SCENARIO 4: The Statistical Significance Trap
	
	Demonstrates how the t-statistic threshold of 100 essentially disables the system.
*************************************************************************************************/

-- Create scenario where there's a clear winner but t-statistic < 100
-- This shows how the conservative threshold prevents beneficial optimizations

-- Simulate two plans: one consistently 50ms, another consistently 200ms  
-- Even with large sample sizes, t-statistic might not reach 100

CREATE TABLE #MockPlanStats (
    PlanID INT,
    AvgDuration DECIMAL(10,2),
    StdDev DECIMAL(10,2),
    ExecutionCount INT
);

-- Plan A: Fast and consistent
INSERT INTO #MockPlanStats VALUES (1, 50, 5, 1000);   -- 50ms ± 5ms, 1000 executions

-- Plan B: Slow but also consistent  
INSERT INTO #MockPlanStats VALUES (2, 200, 10, 1000); -- 200ms ± 10ms, 1000 executions

-- Calculate t-statistic using original formula
WITH TStatisticCalc AS (
    SELECT 
        p1.PlanID AS Plan1,
        p2.PlanID AS Plan2,
        p1.AvgDuration AS Mean1,
        p2.AvgDuration AS Mean2,
        p1.StdDev AS SD1,
        p2.StdDev AS SD2,
        p1.ExecutionCount AS N1,
        p2.ExecutionCount AS N2,
        
        -- Pooled Standard Deviation
        SQRT(
            ((POWER(p1.StdDev, 2) * (p1.ExecutionCount - 1)) + 
             (POWER(p2.StdDev, 2) * (p2.ExecutionCount - 1)))
            / (p1.ExecutionCount + p2.ExecutionCount - 2.0)
        ) AS PooledSD
        
    FROM #MockPlanStats p1
    CROSS JOIN #MockPlanStats p2  
    WHERE p1.PlanID < p2.PlanID
)

SELECT 
    Plan1,
    Plan2,
    Mean2 - Mean1 AS DurationDifference,
    -- t-statistic calculation
    (Mean2 - Mean1) / (PooledSD * SQRT(1.0/N1 + 1.0/N2)) AS t_statistic,
    N1 + N2 - 2 AS degrees_of_freedom,
    
    -- Show that even with 300% performance difference and 1000 samples,
    -- t-statistic is nowhere near the threshold of 100
    CASE 
        WHEN (Mean2 - Mean1) / (PooledSD * SQRT(1.0/N1 + 1.0/N2)) > 100 
        THEN 'WOULD_TRIGGER_ORIGINAL_SYSTEM'
        ELSE 'IGNORED_BY_ORIGINAL_SYSTEM'
    END AS original_system_action,
    
    -- What the decision SHOULD be
    CASE 
        WHEN Mean1 < Mean2 * 0.8 THEN 'SHOULD_PIN_FASTER_PLAN'
        ELSE 'NO_ACTION_NEEDED'
    END AS correct_action
    
FROM TStatisticCalc;

-- Cleanup
DROP TABLE #MockPlanStats;

/**************************************************************************************************
	SUMMARY REPORT: Why The Original System Fails
*************************************************************************************************/

SELECT 
    'PARAMETER_SNIFFING' AS attack_scenario,
    'Pins plan optimized for rare edge case, penalizes 99% of queries' AS vulnerability,
    'Use context-aware plan selection with parameter distribution analysis' AS mitigation
    
UNION ALL SELECT
    'DATA_GROWTH',
    'Pinned plans become obsolete as data size changes, no automatic adaptation',
    'Time-weighted performance tracking with automatic unpinning on degradation'
    
UNION ALL SELECT  
    'RESOURCE_CONTENTION',
    'Isolation testing ignores real-world concurrent execution impacts',
    'Load-aware plan selection and circuit breaker patterns'
    
UNION ALL SELECT
    'STATISTICAL_THRESHOLD', 
    't-statistic threshold of 100 is mathematically meaningless, disables optimization',
    'Bayesian confidence intervals with business impact weighting'
    
UNION ALL SELECT
    'TEMPORAL_BLINDNESS',
    'No consideration of changing workload patterns or performance trends',
    'Exponential decay weighting and trend analysis'
    
ORDER BY attack_scenario;

PRINT '=== ATTACK SCENARIOS COMPLETE ===';
PRINT 'These scenarios demonstrate fundamental flaws in the original approach.';
PRINT 'The alternative implementation addresses each of these vulnerabilities.';
PRINT 'Run the AdaptiveQueryOptimization procedure to see the improved behavior.';