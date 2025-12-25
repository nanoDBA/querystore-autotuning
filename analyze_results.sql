USE QSTest;
GO

-- Let's manually inspect the Query Store data and calculate what the procedure saw
SELECT 'Raw Query Store Data' as Analysis;

-- First, let's see what queries we have
SELECT DISTINCT
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 100) as query_text_truncated,
    COUNT(DISTINCT p.plan_id) as plan_count
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE qt.query_sql_text LIKE '%Orders%CustomerID%'
GROUP BY q.query_id, qt.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1;  -- Only queries with multiple plans

-- Now let's look at the execution stats for queries with multiple plans
SELECT 'Plan Performance Analysis' as Analysis;

SELECT 
    q.query_id,
    p.plan_id,
    SUM(rs.count_executions * rs.avg_duration) / SUM(rs.count_executions) AS weighted_avg_duration,
    SQRT(SUM((rs.count_executions - 1) * POWER(rs.stdev_duration, 2)) / SUM(rs.count_executions - 1)) AS pooled_stdev,
    SUM(rs.count_executions) AS total_executions,
    MIN(rs.avg_duration) as min_avg_duration,
    MAX(rs.avg_duration) as max_avg_duration
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id  
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE '%Orders%CustomerID%'
  AND rs.count_executions > 1
  AND rs.execution_type = 0
GROUP BY q.query_id, p.plan_id
ORDER BY q.query_id, weighted_avg_duration;

-- Let's also check the configuration values being used
SELECT 'Current Configuration' as Analysis;
SELECT * FROM QSAutomation.Configuration;

-- Check if there are any queries that should trigger but don't
SELECT 'Potential Optimization Candidates' as Analysis;

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
)
SELECT 
    ps1.query_id,
    ps1.plan_id as fastest_plan,
    ps1.AverageDuration as fastest_duration,
    ps1.N as fastest_N,
    ps2.plan_id as slowest_plan, 
    ps2.AverageDuration as slowest_duration,
    ps2.N as slowest_N,
    -- Manual t-statistic calculation
    (ps2.AverageDuration - ps1.AverageDuration) /
    (SQRT((POWER(ps1.PooledDurationSTDev, 2) * (ps1.N - 1) + POWER(ps2.PooledDurationSTDev, 2) * (ps2.N - 1)) / (ps1.N + ps2.N - 2)) *
     SQRT(1.0/ps1.N + 1.0/ps2.N)) as calculated_t_statistic,
    (ps1.N + ps2.N - 2) as degrees_of_freedom,
    (ps2.AverageDuration - ps1.AverageDuration) as duration_difference_ms
FROM PlanStats ps1
JOIN PlanStats ps2 ON ps1.query_id = ps2.query_id AND ps1.plan_id != ps2.plan_id
WHERE ps1.AverageDuration < ps2.AverageDuration  -- ps1 is faster
ORDER BY calculated_t_statistic DESC;
GO