USE QSTest;
GO

-- Test QSAutomation with real Query Store data
PRINT 'Testing QSAutomation with Real Query Store Data'
PRINT '==============================================='
GO

-- First, let's see what Query Store actually captured
SELECT 
    'Current Query Store Data' as Analysis,
    q.query_id,
    p.plan_id,
    rs.count_executions,
    rs.avg_duration,
    rs.stdev_duration,
    SUBSTRING(qt.query_sql_text, 1, 60) as query_sample
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.execution_type = 0
ORDER BY q.query_id, p.plan_id;
GO

-- Now run the High Variation Check to see if it finds anything
PRINT 'Running QSAutomation High Variation Check...'
EXEC QSAutomation.QueryStore_HighVariationCheck;
GO

-- Check what the automation system found
SELECT 'QSAutomation Results' as Analysis;

SELECT 'Queries tracked by automation:' as Info;
SELECT * FROM QSAutomation.Query;

SELECT 'Activity log entries:' as Info;  
SELECT * FROM QSAutomation.ActivityLog;
GO

-- Let's manually check if any queries meet the thresholds
WITH QueryAnalysis AS (
    SELECT 
        q.query_id,
        COUNT(DISTINCT p.plan_id) as plan_count,
        MIN(rs.avg_duration) as min_duration,
        MAX(rs.avg_duration) as max_duration,
        MAX(rs.avg_duration) - MIN(rs.avg_duration) as duration_delta,
        SUM(rs.count_executions) as total_executions
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON q.query_id = p.query_id
    JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    WHERE rs.execution_type = 0
    GROUP BY q.query_id
)
SELECT 
    'Manual Threshold Analysis' as Analysis,
    query_id,
    plan_count,
    min_duration,
    max_duration, 
    duration_delta,
    total_executions,
    CASE 
        WHEN plan_count > 1 AND duration_delta > 500 AND total_executions > 10 
        THEN 'POTENTIAL_CANDIDATE'
        WHEN plan_count > 1 
        THEN 'MULTIPLE_PLANS_LOW_DELTA' 
        WHEN duration_delta > 500
        THEN 'HIGH_DELTA_SINGLE_PLAN'
        ELSE 'NO_OPTIMIZATION_OPPORTUNITY'
    END as candidate_status
FROM QueryAnalysis
ORDER BY duration_delta DESC;
GO

PRINT 'Real data testing completed.'
GO