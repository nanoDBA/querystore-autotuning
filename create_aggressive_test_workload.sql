USE QSTest;
GO

-- Create aggressive test workload to ensure Query Store capture
PRINT 'Creating aggressive test workload for Query Store capture...'
PRINT '============================================================'
GO

-- Create more complex test tables
DROP TABLE IF EXISTS QSTest.dbo.PerformanceTest;
CREATE TABLE QSTest.dbo.PerformanceTest (
    ID int IDENTITY(1,1) PRIMARY KEY,
    CategoryID int,
    SearchValue varchar(100),
    LargeData varchar(4000),
    NumericValue decimal(18,2),
    DateValue datetime
);

-- Insert substantial test data (10,000 rows)
WITH NumberSequence AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1 FROM NumberSequence WHERE n < 10000
)
INSERT INTO QSTest.dbo.PerformanceTest (CategoryID, SearchValue, LargeData, NumericValue, DateValue)
SELECT 
    (n % 100) + 1 as CategoryID,
    'SearchValue' + CAST(n AS varchar(10)) as SearchValue,
    REPLICATE('Data' + CAST(n AS varchar(10)), 50) as LargeData,
    RAND(n) * 10000 as NumericValue,
    DATEADD(day, -(n % 365), GETDATE()) as DateValue
FROM NumberSequence
OPTION (MAXRECURSION 10000);
GO

-- Create indexes for different plan scenarios
CREATE INDEX IX_PerformanceTest_CategoryID ON QSTest.dbo.PerformanceTest(CategoryID);
CREATE INDEX IX_PerformanceTest_SearchValue ON QSTest.dbo.PerformanceTest(SearchValue);  
CREATE INDEX IX_PerformanceTest_DateValue ON QSTest.dbo.PerformanceTest(DateValue);
GO

-- Update statistics to ensure plan stability
UPDATE STATISTICS QSTest.dbo.PerformanceTest;
GO

PRINT 'Test data created. Starting workload execution...'

-- Workload 1: Parameter sniffing scenario (should generate multiple plans)
DECLARE @Counter int = 1;
DECLARE @CategoryID int;
DECLARE @SearchValue varchar(100);

WHILE @Counter <= 50
BEGIN
    -- Mix of high and low cardinality parameter values
    IF @Counter % 10 = 0 
        SET @CategoryID = 1  -- High cardinality (100 rows)
    ELSE
        SET @CategoryID = 50 + (@Counter % 50)  -- Lower cardinality (1-50 rows typically)
    
    -- Execute parameterized query
    EXEC sp_executesql 
        N'SELECT COUNT(*), AVG(NumericValue) FROM QSTest.dbo.PerformanceTest WHERE CategoryID = @Cat',
        N'@Cat int',
        @Cat = @CategoryID;
    
    SET @Counter = @Counter + 1;
END
GO

-- Wait for Query Store capture
WAITFOR DELAY '00:00:10';
GO

-- Workload 2: Different query patterns with hints to force different plans
DECLARE @Counter int = 1;
WHILE @Counter <= 30
BEGIN
    -- Force index scan (slower)
    SELECT ID, SearchValue, NumericValue 
    FROM QSTest.dbo.PerformanceTest WITH (INDEX(IX_PerformanceTest_CategoryID))
    WHERE CategoryID BETWEEN 1 AND 10
    ORDER BY NumericValue;
    
    SET @Counter = @Counter + 1;
END
GO

WAITFOR DELAY '00:00:05';
GO

DECLARE @Counter int = 1; 
WHILE @Counter <= 40
BEGIN
    -- Different access pattern (faster)
    SELECT ID, SearchValue, NumericValue
    FROM QSTest.dbo.PerformanceTest WITH (INDEX(IX_PerformanceTest_DateValue))  
    WHERE DateValue > DATEADD(day, -30, GETDATE())
    ORDER BY DateValue;
    
    SET @Counter = @Counter + 1;
END
GO

-- Workload 3: Resource-intensive queries (to ensure capture)
DECLARE @Counter int = 1;
WHILE @Counter <= 20
BEGIN
    -- Cross join to make it resource intensive
    SELECT COUNT(*)
    FROM QSTest.dbo.PerformanceTest p1
    INNER JOIN QSTest.dbo.PerformanceTest p2 ON p1.CategoryID = p2.CategoryID
    WHERE p1.ID <= 100 AND p2.ID <= 100;
    
    SET @Counter = @Counter + 1;
END
GO

-- Final wait for all data to be captured
WAITFOR DELAY '00:00:15';
GO

-- Verify Query Store captured our workload
PRINT 'Query Store capture verification:'
PRINT '================================='

SELECT 
    'Query Store Statistics' as Info,
    COUNT(*) as QueryCount
FROM sys.query_store_query;

SELECT
    q.query_id,
    COUNT(p.plan_id) as PlanCount,
    SUM(rs.count_executions) as TotalExecutions,
    AVG(rs.avg_duration) as AvgDuration,
    SUBSTRING(qt.query_sql_text, 1, 100) as QueryTextSample
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE '%PerformanceTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%'
GROUP BY q.query_id, qt.query_sql_text
HAVING COUNT(p.plan_id) > 1  -- Only queries with multiple plans
ORDER BY TotalExecutions DESC;

PRINT 'Aggressive workload completed. Query Store should now have substantial data for testing.'
GO