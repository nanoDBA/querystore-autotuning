USE QSTest;
GO

-- Test Step 2: Invalid Plan Check
-- This tests the system's ability to detect and handle invalid forced plans

PRINT 'Testing Step 2: Invalid Plan Check'
PRINT '================================='
GO

-- First, let's create a scenario that could lead to an invalid plan
-- We'll create a table, generate some plans, force one, then drop an index

-- Create a test table for invalid plan scenarios
DROP TABLE IF EXISTS QSTest.dbo.InvalidPlanTest;
CREATE TABLE QSTest.dbo.InvalidPlanTest (
    ID int IDENTITY(1,1) PRIMARY KEY,
    SearchCol varchar(50),
    DataCol varchar(100)
);

-- Insert some test data
INSERT INTO QSTest.dbo.InvalidPlanTest (SearchCol, DataCol)
SELECT 
    'Value' + CAST(n AS varchar(10)),
    'Data' + CAST(n AS varchar(10))
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as n
    FROM sys.objects a
    CROSS JOIN sys.objects b
) nums
WHERE n <= 1000;

-- Create an index
CREATE INDEX IX_InvalidPlanTest_SearchCol ON QSTest.dbo.InvalidPlanTest(SearchCol);
GO

-- Execute a query multiple times to get it in Query Store
DECLARE @i int = 1;
WHILE @i <= 10
BEGIN
    SELECT * FROM QSTest.dbo.InvalidPlanTest WHERE SearchCol = 'Value500';
    SET @i = @i + 1;
END
GO

-- Wait for Query Store to capture
WAITFOR DELAY '00:00:05';
GO

-- Check what plans we have
PRINT 'Query Store plans before forcing:'
SELECT 
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.last_force_failure_reason,
    p.last_force_failure_reason_desc,
    SUBSTRING(qt.query_sql_text, 1, 100) as query_text
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE qt.query_sql_text LIKE '%InvalidPlanTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%';
GO

-- Force a plan (simulate what QSAutomation would do)
DECLARE @QueryID bigint, @PlanID bigint;

SELECT TOP 1 
    @QueryID = q.query_id,
    @PlanID = p.plan_id
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id  
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE qt.query_sql_text LIKE '%InvalidPlanTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%';

IF @QueryID IS NOT NULL AND @PlanID IS NOT NULL
BEGIN
    PRINT 'Forcing plan ' + CAST(@PlanID AS varchar(10)) + ' for query ' + CAST(@QueryID AS varchar(10));
    EXEC sp_query_store_force_plan @QueryID, @PlanID;
    
    -- Add to automation tracking
    INSERT INTO QSAutomation.Query (QueryID, StatusID, QueryCreationDatetime, QueryPlanID, PinDate)
    VALUES (@QueryID, 1, GETDATE(), @PlanID, GETDATE());
END
ELSE
BEGIN
    PRINT 'No suitable query/plan found to force';
END
GO

-- Verify plan is forced
PRINT 'Query Store plans after forcing:'
SELECT 
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.last_force_failure_reason,
    p.last_force_failure_reason_desc
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE qt.query_sql_text LIKE '%InvalidPlanTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%'
  AND p.is_forced_plan = 1;
GO

-- Now create a scenario that makes the plan invalid
-- Drop the index that the plan might depend on
PRINT 'Dropping index to potentially invalidate forced plan...'
DROP INDEX IX_InvalidPlanTest_SearchCol ON QSTest.dbo.InvalidPlanTest;
GO

-- Try to execute the query to trigger plan failure
PRINT 'Executing query to test plan validity...'
SELECT * FROM QSTest.dbo.InvalidPlanTest WHERE SearchCol = 'Value500';
GO

-- Check if plan failure was recorded
PRINT 'Checking for plan failures:'
SELECT 
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.last_force_failure_reason,
    p.last_force_failure_reason_desc,
    p.force_failure_count
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE qt.query_sql_text LIKE '%InvalidPlanTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%';
GO

-- Now test Step 2: Invalid Plan Check procedure
PRINT 'Running Step 2: Invalid Plan Check...'
EXEC QSAutomation.QueryStore_InvalidPlanCheck;
GO

-- Check results
PRINT 'Results after running Invalid Plan Check:'

PRINT 'QSAutomation.Query table:'
SELECT * FROM QSAutomation.Query;

PRINT 'QSAutomation.ActivityLog table:'  
SELECT * FROM QSAutomation.ActivityLog;

PRINT 'Forced plans remaining in Query Store:'
SELECT 
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.last_force_failure_reason,
    p.last_force_failure_reason_desc
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE p.is_forced_plan = 1;
GO

PRINT 'Step 2 Invalid Plan Check test completed.'
GO