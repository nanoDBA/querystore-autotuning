USE QSTest;
GO

-- Execute the High Variation Check procedure  
PRINT 'Executing QueryStore_HighVariationCheck...'
EXEC QSAutomation.QueryStore_HighVariationCheck;
GO

-- Check results
PRINT 'Checking results...'
SELECT 'Query Automation Results' as Analysis;

SELECT 
    QueryID,
    StatusID, 
    QueryCreationDatetime,
    QueryPlanID,
    PinDate
FROM QSAutomation.Query;

SELECT 
    ActivityLogID,
    ActivityDate,
    QueryID,
    QueryPlanID,
    LEFT(ActionDetail, 100) as ActionDetail_Truncated
FROM QSAutomation.ActivityLog;

-- Check actual Query Store data to see what should have been detected
PRINT 'Query Store Analysis...'
SELECT 'Query Store Plan Analysis' as Analysis;

WITH PlanStats AS (
    SELECT 
        p.query_id,
        p.plan_id,
        SUM(rs.count_executions * rs.avg_duration) / SUM(rs.count_executions) AS AverageDuration,
        SQRT(SUM((rs.count_executions - 1) * POWER(rs.stdev_duration, 2)) / SUM(rs.count_executions - 1)) AS PooledDurationSTDev,
        SUM(rs.count_executions) AS N
    FROM sys.query_store_plan p
    JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    WHERE rs.count_executions > 1 AND rs.execution_type = 0
    GROUP BY p.query_id, p.plan_id
),
QueryPlanComparisons AS (
    SELECT 
        ps1.query_id,
        ps1.plan_id as fastest_plan,
        ps1.AverageDuration as fastest_duration,
        ps1.N as fastest_N,
        ps1.PooledDurationSTDev as fastest_stdev,
        ps2.plan_id as slowest_plan, 
        ps2.AverageDuration as slowest_duration,
        ps2.N as slowest_N,
        ps2.PooledDurationSTDev as slowest_stdev,
        -- Manual t-statistic calculation matching the procedure
        (ps2.AverageDuration - ps1.AverageDuration) /
        (SQRT((POWER(ps1.PooledDurationSTDev, 2) * (ps1.N - 1) + POWER(ps2.PooledDurationSTDev, 2) * (ps2.N - 1)) / (ps1.N + ps2.N - 2)) *
         SQRT(1.0/ps1.N + 1.0/ps2.N)) as calculated_t_statistic,
        (ps1.N + ps2.N - 2) as degrees_of_freedom,
        (ps2.AverageDuration - ps1.AverageDuration) as duration_difference_ms
    FROM PlanStats ps1
    JOIN PlanStats ps2 ON ps1.query_id = ps2.query_id AND ps1.plan_id != ps2.plan_id
    WHERE ps1.AverageDuration <= ps2.AverageDuration  -- ps1 is faster or equal
)
SELECT 
    query_id,
    fastest_plan,
    fastest_duration,
    slowest_plan,
    slowest_duration,
    calculated_t_statistic,
    degrees_of_freedom,
    duration_difference_ms,
    CASE 
        WHEN calculated_t_statistic > 100 AND degrees_of_freedom > 10 AND duration_difference_ms > 500 
        THEN 'SHOULD PIN'
        WHEN calculated_t_statistic > 10 
        THEN 'WOULD PIN WITH LOWER THRESHOLD'
        ELSE 'NO ACTION'
    END as decision
FROM QueryPlanComparisons
ORDER BY calculated_t_statistic DESC;

-- Show configuration for reference
SELECT 'Configuration Values' as Analysis;
SELECT ConfigurationName, ConfigurationValue 
FROM QSAutomation.Configuration 
WHERE ConfigurationName IN ('t-Statistic Threshold', 'DF Threshold', 'High Variation Duration Threshold (MS)');
GO