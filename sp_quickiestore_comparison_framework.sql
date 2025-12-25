USE QSTest;
GO

-- sp_QuickieStore Comparative Analysis Framework
-- Note: Actual sp_QuickieStore would be downloaded from:
-- https://github.com/erikdarlingdata/DarlingData/blob/main/sp_QuickieStore/sp_QuickieStore.sql

PRINT 'sp_QuickieStore vs QSAutomation Comparative Analysis Framework'
PRINT '=============================================================='
GO

-- Create a simulated analysis based on what sp_QuickieStore would typically identify
-- This demonstrates the comparison methodology for when the actual tool is available

-- 1. What would sp_QuickieStore identify as problem queries?
SELECT 
    'sp_QuickieStore Style Analysis - Top Problem Queries' as Analysis,
    q.query_id,
    p.plan_id,
    rs.count_executions,
    rs.avg_duration as avg_duration_ms,
    rs.avg_cpu_time as avg_cpu_time_ms,
    rs.avg_logical_io_reads,
    rs.avg_physical_io_reads,
    -- Calculate "problem score" similar to sp_QuickieStore approach
    (rs.avg_duration * rs.count_executions) as total_duration_impact,
    (rs.avg_cpu_time * rs.count_executions) as total_cpu_impact,
    SUBSTRING(qt.query_sql_text, 1, 100) as query_text_sample,
    CASE 
        WHEN rs.avg_duration > 1000 THEN 'HIGH_DURATION'
        WHEN rs.avg_cpu_time > 1000 THEN 'HIGH_CPU'
        WHEN rs.avg_logical_io_reads > 10000 THEN 'HIGH_IO'
        ELSE 'NORMAL'
    END as problem_category
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.execution_type = 0
  AND qt.query_sql_text NOT LIKE '%sys.%'
  AND rs.count_executions > 0
ORDER BY total_duration_impact DESC;
GO

-- 2. QSAutomation findings recap
SELECT 'QSAutomation Analysis Results' as Analysis;

-- Show what QSAutomation found (should be nothing with default thresholds)
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN 'No queries pinned - conservative thresholds working as designed'
        ELSE CAST(COUNT(*) AS varchar(10)) + ' queries tracked by automation'
    END as automation_result
FROM QSAutomation.Query;

-- Show potential candidates that QSAutomation considered but didn't act on
WITH QSAutomationStyle AS (
    SELECT 
        q.query_id,
        COUNT(DISTINCT p.plan_id) as plan_count,
        MIN(rs.avg_duration) as fastest_plan_ms,
        MAX(rs.avg_duration) as slowest_plan_ms,
        MAX(rs.avg_duration) - MIN(rs.avg_duration) as duration_delta_ms,
        SUM(rs.count_executions) as total_executions,
        CASE 
            WHEN COUNT(DISTINCT p.plan_id) > 1 
             AND MAX(rs.avg_duration) - MIN(rs.avg_duration) > 500
             AND SUM(rs.count_executions) > 10
            THEN 'WOULD_PIN_WITH_DEFAULTS'
            WHEN COUNT(DISTINCT p.plan_id) > 1
             AND MAX(rs.avg_duration) - MIN(rs.avg_duration) > 100
            THEN 'WOULD_PIN_WITH_LOWER_THRESHOLD'
            ELSE 'NO_ACTION'
        END as qsautomation_decision
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON q.query_id = p.query_id
    JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    WHERE rs.execution_type = 0
    GROUP BY q.query_id
)
SELECT 
    'QSAutomation Candidate Analysis' as Analysis,
    *
FROM QSAutomationStyle
WHERE plan_count > 1
ORDER BY duration_delta_ms DESC;
GO

-- 3. Comparative analysis framework
SELECT 'Comparative Analysis Framework' as Analysis;

-- This would compare findings between the two tools
WITH ComparisonFramework AS (
    SELECT 
        q.query_id,
        -- sp_QuickieStore style prioritization (total impact)
        (rs.avg_duration * rs.count_executions) as sp_quickiestore_score,
        CASE 
            WHEN (rs.avg_duration * rs.count_executions) > 10000 THEN 'sp_QuickieStore_HIGH_PRIORITY'
            WHEN (rs.avg_duration * rs.count_executions) > 1000 THEN 'sp_QuickieStore_MEDIUM_PRIORITY'  
            ELSE 'sp_QuickieStore_LOW_PRIORITY'
        END as sp_quickiestore_priority,
        
        -- QSAutomation style prioritization (plan variation + thresholds)
        CASE 
            WHEN COUNT(DISTINCT p.plan_id) > 1 
             AND MAX(rs.avg_duration) - MIN(rs.avg_duration) > 500
            THEN 'QSAutomation_ACTIONABLE'
            WHEN COUNT(DISTINCT p.plan_id) > 1
            THEN 'QSAutomation_POTENTIAL'
            ELSE 'QSAutomation_NO_ACTION'
        END as qsautomation_priority,
        
        -- Analysis comparison
        CASE 
            WHEN COUNT(DISTINCT p.plan_id) > 1 
             AND (rs.avg_duration * rs.count_executions) > 10000
            THEN 'BOTH_TOOLS_AGREE_HIGH'
            WHEN COUNT(DISTINCT p.plan_id) > 1
            THEN 'QSAUTOMATION_SEES_POTENTIAL'
            WHEN (rs.avg_duration * rs.count_executions) > 10000
            THEN 'SP_QUICKIESTORE_SEES_PROBLEM'
            ELSE 'BOTH_TOOLS_AGREE_LOW'
        END as tool_agreement
        
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON q.query_id = p.query_id
    JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    WHERE rs.execution_type = 0
    GROUP BY q.query_id, rs.avg_duration, rs.count_executions
)
SELECT 
    query_id,
    sp_quickiestore_priority,
    qsautomation_priority,
    tool_agreement,
    sp_quickiestore_score
FROM ComparisonFramework
WHERE sp_quickiestore_priority != 'sp_QuickieStore_LOW_PRIORITY'
   OR qsautomation_priority != 'QSAutomation_NO_ACTION'
ORDER BY sp_quickiestore_score DESC;
GO

-- 4. Key insights from comparison
SELECT 'Key Insights from Tool Comparison' as Analysis;

PRINT 'Expected comparison insights:'
PRINT '1. sp_QuickieStore focuses on total business impact (duration × executions)'
PRINT '2. QSAutomation focuses on plan variation and statistical significance'  
PRINT '3. Both tools should identify the same "obvious" problem queries'
PRINT '4. QSAutomation provides more conservative automation decisions'
PRINT '5. sp_QuickieStore provides broader visibility into performance issues'
PRINT ''
PRINT 'For actual comparison, install sp_QuickieStore from:'
PRINT 'https://github.com/erikdarlingdata/DarlingData'
GO

-- 5. Recommendation for actual implementation
PRINT 'Recommended Production Workflow:'
PRINT '1. Use sp_QuickieStore for broad performance issue identification'
PRINT '2. Use QSAutomation for conservative plan optimization automation'  
PRINT '3. Human experts review sp_QuickieStore findings for manual optimization'
PRINT '4. QSAutomation handles obvious plan variation issues automatically'
PRINT '5. Both tools provide complementary value in different scenarios'
GO