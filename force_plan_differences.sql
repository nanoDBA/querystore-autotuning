USE QSTest;
GO

-- Clear Query Store data to start fresh
ALTER DATABASE QSTest SET QUERY_STORE CLEAR;
GO

-- Create a scenario that will definitely generate different plans
-- First, execute with a hint to force one plan type
DECLARE @i int = 1;
WHILE @i <= 15
BEGIN
    -- Force index scan (slower plan)
    SELECT OrderID, Amount, Status 
    FROM Orders WITH (INDEX(IX_Orders_OrderDate))
    WHERE CustomerID = 'WHALE001';
    SET @i = @i + 1;
END;
GO

-- Wait for Query Store to capture
WAITFOR DELAY '00:00:10';
GO

-- Now execute same query with different hint (faster plan)
DECLARE @i int = 1;
WHILE @i <= 20
BEGIN
    -- Force index seek (faster plan) 
    SELECT OrderID, Amount, Status
    FROM Orders WITH (INDEX(IX_Orders_CustomerID))
    WHERE CustomerID = 'WHALE001';
    SET @i = @i + 1;
END;
GO

-- Wait for Query Store
WAITFOR DELAY '00:00:10';
GO

-- Create another test case with OPTION(RECOMPILE) vs normal execution
DECLARE @i int = 1;
WHILE @i <= 12  
BEGIN
    -- This will be compiled fresh each time
    SELECT COUNT(*) FROM Orders WHERE CustomerID = 'WHALE001' OPTION(RECOMPILE);
    SET @i = @i + 1;
END;
GO

WAITFOR DELAY '00:00:05';
GO

DECLARE @i int = 1;
WHILE @i <= 18
BEGIN
    -- This will use cached plan
    SELECT COUNT(*) FROM Orders WHERE CustomerID = 'WHALE001';
    SET @i = @i + 1;
END;
GO

-- Force Query Store to flush data
ALTER DATABASE QSTest SET QUERY_STORE (DATA_FLUSH_INTERVAL_SECONDS = 1);
WAITFOR DELAY '00:00:05';
ALTER DATABASE QSTest SET QUERY_STORE (DATA_FLUSH_INTERVAL_SECONDS = 60);
GO

-- Now check what we have
SELECT 'Plan Variation Check After Forced Differences' as Analysis;

SELECT 
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 80) as query_text,
    p.plan_id,
    rs.count_executions,
    rs.avg_duration,
    rs.stdev_duration,
    p.is_forced_plan
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id  
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.execution_type = 0
  AND qt.query_sql_text LIKE '%Orders%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%'
ORDER BY q.query_id, rs.avg_duration;
GO