USE QSTest;
GO

-- Check Query Store data population after aggressive workload
PRINT 'Query Store Data Analysis After Aggressive Workload'
PRINT '================================================='
GO

-- Overall Query Store statistics
SELECT 
    'Overall Statistics' as Analysis,
    COUNT(DISTINCT q.query_id) as TotalQueries,
    COUNT(DISTINCT p.plan_id) as TotalPlans,
    SUM(rs.count_executions) as TotalExecutions,
    AVG(rs.avg_duration) as AvgDurationMS
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.execution_type = 0;
GO

-- Queries with multiple plans (prime candidates for QSAutomation)
SELECT 
    'Queries with Multiple Plans' as Analysis,
    q.query_id,
    COUNT(DISTINCT p.plan_id) as PlanCount,
    SUM(rs.count_executions) as TotalExecutions,
    MIN(rs.avg_duration) as FastestPlanDuration,
    MAX(rs.avg_duration) as SlowestPlanDuration,
    MAX(rs.avg_duration) - MIN(rs.avg_duration) as DurationDelta,
    CASE 
        WHEN MAX(rs.avg_duration) - MIN(rs.avg_duration) > 500 
        THEN 'MEETS_DURATION_THRESHOLD'
        ELSE 'BELOW_DURATION_THRESHOLD'
    END as DurationThresholdStatus,
    SUBSTRING(qt.query_sql_text, 1, 100) as QueryTextSample
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.execution_type = 0
  AND qt.query_sql_text LIKE '%PerformanceTest%'
  AND qt.query_sql_text NOT LIKE '%sys.query_store%'
GROUP BY q.query_id, qt.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY DurationDelta DESC;
GO

-- Detailed plan analysis for top candidate query
WITH TopCandidate AS (
    SELECT TOP 1 q.query_id
    FROM sys.query_store_query q
    JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    JOIN sys.query_store_plan p ON q.query_id = p.query_id
    JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    WHERE rs.execution_type = 0
      AND qt.query_sql_text LIKE '%PerformanceTest%'
      AND qt.query_sql_text NOT LIKE '%sys.query_store%'
    GROUP BY q.query_id
    HAVING COUNT(DISTINCT p.plan_id) > 1
      AND MAX(rs.avg_duration) - MIN(rs.avg_duration) > 0
    ORDER BY MAX(rs.avg_duration) - MIN(rs.avg_duration) DESC
)
SELECT 
    'Detailed Plan Analysis for Best Candidate' as Analysis,
    p.plan_id,
    rs.count_executions,
    rs.avg_duration,
    rs.stdev_duration,
    CASE 
        WHEN rs.avg_duration = MIN(rs.avg_duration) OVER() THEN 'FASTEST_PLAN'
        WHEN rs.avg_duration = MAX(rs.avg_duration) OVER() THEN 'SLOWEST_PLAN' 
        ELSE 'MIDDLE_PLAN'
    END as PlanCategory
FROM sys.query_store_plan p
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
JOIN TopCandidate tc ON p.query_id = tc.query_id
WHERE rs.execution_type = 0
ORDER BY rs.avg_duration;
GO

-- Manual t-statistic calculation for validation
WITH PlanStats AS (
    SELECT TOP 1
        q.query_id,
        MIN(CASE WHEN rn_asc = 1 THEN p.plan_id END) as FastestPlanID,
        MIN(CASE WHEN rn_asc = 1 THEN rs.avg_duration END) as FastestDuration,
        MIN(CASE WHEN rn_asc = 1 THEN rs.count_executions END) as FastestN,
        MIN(CASE WHEN rn_asc = 1 THEN rs.stdev_duration END) as FastestStdev,
        MAX(CASE WHEN rn_desc = 1 THEN p.plan_id END) as SlowestPlanID,
        MAX(CASE WHEN rn_desc = 1 THEN rs.avg_duration END) as SlowestDuration,
        MAX(CASE WHEN rn_desc = 1 THEN rs.count_executions END) as SlowestN,
        MAX(CASE WHEN rn_desc = 1 THEN rs.stdev_duration END) as SlowestStdev
    FROM (
        SELECT 
            q.query_id,
            p.plan_id,
            rs.avg_duration,
            rs.count_executions,
            rs.stdev_duration,
            ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rs.avg_duration ASC) as rn_asc,
            ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rs.avg_duration DESC) as rn_desc
        FROM sys.query_store_query q
        JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
        JOIN sys.query_store_plan p ON q.query_id = p.query_id
        JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
        WHERE rs.execution_type = 0
          AND qt.query_sql_text LIKE '%PerformanceTest%'
          AND qt.query_sql_text NOT LIKE '%sys.query_store%'
          AND rs.count_executions > 1
    ) ranked
    GROUP BY q.query_id
    HAVING COUNT(DISTINCT ranked.plan_id) > 1
      AND MAX(CASE WHEN rn_desc = 1 THEN rs.avg_duration END) - 
         MIN(CASE WHEN rn_asc = 1 THEN rs.avg_duration END) > 0
    ORDER BY MAX(CASE WHEN rn_desc = 1 THEN rs.avg_duration END) - 
             MIN(CASE WHEN rn_asc = 1 THEN rs.avg_duration END) DESC
)
SELECT 
    'Manual t-Statistic Calculation' as Analysis,
    query_id,
    FastestPlanID,
    FastestDuration,
    FastestN,
    SlowestPlanID, 
    SlowestDuration,
    SlowestN,
    (SlowestDuration - FastestDuration) as DurationDifference,
    -- Manual t-statistic calculation
    CASE 
        WHEN FastestN > 1 AND SlowestN > 1 THEN
            (SlowestDuration - FastestDuration) /
            (SQRT((POWER(ISNULL(FastestStdev, 1), 2) * (FastestN - 1) + 
                   POWER(ISNULL(SlowestStdev, 1), 2) * (SlowestN - 1)) / 
                  (FastestN + SlowestN - 2)) *
             SQRT(1.0/FastestN + 1.0/SlowestN))
        ELSE NULL
    END as CalculatedTStatistic,
    (FastestN + SlowestN - 2) as DegreesOfFreedom,
    CASE 
        WHEN (SlowestDuration - FastestDuration) > 500 
         AND (FastestN + SlowestN - 2) > 10
        THEN 'MEETS_BASIC_THRESHOLDS'
        ELSE 'BELOW_THRESHOLDS'
    END as ThresholdStatus
FROM PlanStats;
GO

PRINT 'Query Store data analysis completed. Ready for QSAutomation testing.'
GO