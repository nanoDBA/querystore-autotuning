USE QSTest;
GO

-- Test Query 1: This will generate different plans based on parameter values
-- First, execute with high cardinality customer (should use index scan)
DECLARE @i int = 1;
WHILE @i <= 20
BEGIN
    EXEC sp_executesql N'SELECT OrderID, Amount FROM Orders WHERE CustomerID = @CustomerID', 
         N'@CustomerID varchar(10)', @CustomerID = 'WHALE001';
    SET @i = @i + 1;
END;
GO

-- Wait a moment for Query Store to capture
WAITFOR DELAY '00:00:05';
GO

-- Now execute same query with low cardinality customers (should use index seek)
DECLARE @i int = 1;
WHILE @i <= 25
BEGIN
    EXEC sp_executesql N'SELECT OrderID, Amount FROM Orders WHERE CustomerID = @CustomerID', 
         N'@CustomerID varchar(10)', @CustomerID = 'CUST500';
    SET @i = @i + 1;
END;
GO

-- Wait for Query Store
WAITFOR DELAY '00:00:05';
GO

-- Force a different plan by using a hint
DECLARE @i int = 1;
WHILE @i <= 15
BEGIN
    EXEC sp_executesql N'SELECT OrderID, Amount FROM Orders WHERE CustomerID = @CustomerID OPTION(FORCE ORDER)', 
         N'@CustomerID varchar(10)', @CustomerID = 'CUST600';
    SET @i = @i + 1;
END;
GO

-- Check Query Store data
SELECT 'Query Store Analysis' as Analysis;

SELECT 
    q.query_id,
    qt.query_sql_text,
    p.plan_id,
    rs.count_executions,
    rs.avg_duration,
    rs.stdev_duration
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE '%Orders%CustomerID%'
ORDER BY q.query_id, p.plan_id;
GO