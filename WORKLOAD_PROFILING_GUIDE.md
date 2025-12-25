# Workload Profiling and Test Environment Setup Guide

## Overview

This guide helps you capture production workload characteristics and replicate them proportionally in test environments with fewer resources.

## Key Concept: Micro-Representation

Even though production might have 32 cores and your test container has 1 core, we can maintain the **same workload characteristics**:

- **Read/Write Ratio** - If production is 75% reads, test will be 75% reads
- **Wait Type Distribution** - If production has 35% PAGEIOLATCH waits, test will too
- **Query Type Mix** - Same proportion of CPU-bound vs IO-bound queries
- **Blocking Patterns** - Similar lock contention patterns scaled down

## Quick Start (3 Steps)

### Step 1: Capture Production Profile (30 seconds)

Run on **PRODUCTION**:
```sql
-- Easiest method - copy/paste friendly
sqlcmd -S production_server -d your_database -i workload_profile_helper.sql -o profile_output.txt
```

Or in SSMS:
1. Open [workload_profile_helper.sql](workload_profile_helper.sql)
2. Execute on production
3. Copy the results grid (Ctrl+A, Ctrl+C)
4. Paste into Excel or text file
5. Save as `production_profile_YYYYMMDD.csv`

### Step 2: Generate Test Environment (5 minutes)

1. Open [generate_scaled_test_workload.sql](generate_scaled_test_workload.sql)
2. Find the `@ProductionProfile` table section (around line 20)
3. Paste the INSERT statements from Step 1
4. Execute on **TEST** environment

This creates:
- WorkloadTest database
- Scaled test data (proportional to your test environment CPU)
- Stored procedures that match production query patterns
- Workload execution procedure

### Step 3: Run Test Workload (10-15 minutes)

```sql
USE [WorkloadTest];

-- Execute workload matching production characteristics
EXEC [dbo].[Execute_ScaledWorkload]
    @DurationMinutes = 15,
    @ReadPercentage = 75.00,  -- Use your production value
    @WritePercentage = 25.00; -- Use your production value
```

This will generate Query Store data matching production patterns!

## Files Overview

| File | Purpose | Run Where | Time |
|------|---------|-----------|------|
| [Wait_Types.sql](Wait_Types.sql) | Original wait stats analysis | Production | 5 sec |
| [workload_profile_helper.sql](workload_profile_helper.sql) | **Easy profile capture** (recommended) | Production | 30 sec |
| [capture_production_workload_profile.sql](capture_production_workload_profile.sql) | Detailed JSON profile | Production | 1 min |
| [generate_scaled_test_workload.sql](generate_scaled_test_workload.sql) | Create test environment | Test | 5 min |

## Detailed Workflow

### Production Environment Tasks

#### Option A: Simple Table Export (Recommended for Easy Copy/Paste)

```sql
-- Run on production
-- File: workload_profile_helper.sql

-- Outputs a clean table you can copy directly
-- Categories captured:
--   - System info (CPUs, Memory, SQL Version)
--   - Read/Write ratios
--   - Top 5 wait types with percentages
--   - Workload classification
```

**What you'll see:**
```
Category    ProfileKey           ProfileValue    Notes
----------- -------------------- --------------- ---------------------------
System      ServerName           PROD-SQL01      Source server name
CPU         LogicalCPUs          32              Total logical CPUs available
IO          ReadPercentage       75.23           Percentage of reads
WaitStats   WaitType1            PAGEIOLATCH_SH  Top 1 wait type
WaitStats   WaitType1Percentage  35.50           Percentage for top 1 wait
```

#### Option B: Comprehensive JSON Export (For Advanced Analysis)

```sql
-- Run on production
-- File: capture_production_workload_profile.sql

-- Outputs detailed JSON for each category:
--   1. Wait Statistics (normalized percentages)
--   2. Read vs Write Workload Ratio
--   3. Blocking Profile
--   4. CPU Utilization Profile
--   5. Query Store Workload Profile
--   6. Transaction Log Activity
--   7. Memory Usage Profile
--   8. Workload Fingerprint Summary
```

**Export Methods:**
1. **Results to Text** (Ctrl+T): Copy JSON output directly
2. **Results to File** (Ctrl+Shift+F): Save to .txt file
3. **Results to Grid**: Copy and paste into JSON file

### Test Environment Tasks

#### 1. Update Configuration

Edit [generate_scaled_test_workload.sql](generate_scaled_test_workload.sql):

```sql
-- Find this section around line 20-50
INSERT INTO @ProductionProfile ([ProfileKey], [ProfileValue])
VALUES
    -- Paste your production values here
    ('PrimaryWorkloadType', 'IO_INTENSIVE'),
    ('ReadPercentage', '75.23'),
    ('WritePercentage', '24.77'),
    ('ProductionCPUs', '32'),
    ('WaitType1', 'PAGEIOLATCH_SH'),
    ('WaitType1Percentage', '35.50'),
    -- ... etc
```

#### 2. Execute Setup Script

```sql
-- This will:
--   1. Calculate scaling factor (test CPUs / production CPUs)
--   2. Create WorkloadTest database
--   3. Enable Query Store
--   4. Create scaled test data
--   5. Create workload procedures
--   6. Create execution procedure

-- Example output:
-- Production CPUs: 32
-- Test CPUs: 4
-- Scaling Factor: 0.125 (12.5%)
-- Workload Type: IO_INTENSIVE
-- Read/Write Ratio: 75% / 25%
```

#### 3. Run Workload

```sql
-- Start workload generation
EXEC [WorkloadTest].[dbo].[Execute_ScaledWorkload]
    @DurationMinutes = 15,
    @ReadPercentage = 75.00,  -- Match production
    @WritePercentage = 25.00; -- Match production

-- Progress will be displayed:
-- Iteration 100 - Elapsed: 1 minutes
-- Iteration 200 - Elapsed: 2 minutes
-- ...
-- Workload execution complete
-- Total Iterations: 1234
```

#### 4. Verify Query Store Capture

```sql
USE [WorkloadTest];

-- Check Query Store has data
SELECT COUNT(*) AS [Queries] FROM sys.query_store_query;
SELECT COUNT(*) AS [Plans] FROM sys.query_store_plan;

-- View workload characteristics
SELECT
    q.query_id,
    COUNT(DISTINCT p.plan_id) AS [PlanCount],
    SUM(rs.count_executions) AS [Executions],
    AVG(rs.avg_duration) AS [AvgDurationMicroseconds]
FROM sys.query_store_query q
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
GROUP BY q.query_id
ORDER BY [Executions] DESC;
```

## Understanding Scaling

### Automatic Scaling Calculations

The script automatically scales data volume based on CPU ratio:

| Test CPUs | Production CPUs | Scaling Factor | Data Rows Created |
|-----------|-----------------|----------------|-------------------|
| 1         | 32              | 3.1% (0.031)   | 10,000           |
| 4         | 32              | 12.5% (0.125)  | 50,000           |
| 8         | 32              | 25% (0.25)     | 100,000          |
| 16        | 32              | 50% (0.5)      | 250,000          |

**The workload characteristics remain constant regardless of scale:**
- Same read/write ratio
- Same wait type distribution
- Same query type mix
- Same blocking patterns

### What Gets Scaled vs What Stays Constant

**Scaled Down:**
- Data volume (fewer rows)
- Absolute execution counts
- Absolute wait times
- Memory usage

**Stays Proportional:**
- Read/Write percentage ✓
- Wait type percentages ✓
- Query type distribution ✓
- CPU vs IO ratio ✓
- Blocking frequency ✓

## Use Cases

### 1. QueryStore Automation Testing

```sql
-- After generating workload:
-- 1. Install QSAutomation schema
-- 2. Run automation procedures
-- 3. Verify plan pinning decisions

USE [WorkloadTest];
-- Install QSAutomation (from main repo scripts)
-- Run Step 1: High Variation Check
EXEC QSAutomation.QueryStore_HighVariationCheck;

-- Check results
SELECT * FROM QSAutomation.Query;
SELECT * FROM QSAutomation.ActivityLog;
```

### 2. Performance Baseline Comparison

```sql
-- Run workload with different configurations
-- Compare Query Store metrics

-- Test 1: Default settings
EXEC [dbo].[Execute_ScaledWorkload] @DurationMinutes = 10;

-- Capture baseline
SELECT * INTO #Baseline
FROM sys.query_store_runtime_stats;

-- Test 2: After tuning/optimization
-- Clear Query Store
ALTER DATABASE [WorkloadTest] SET QUERY_STORE CLEAR ALL;

EXEC [dbo].[Execute_ScaledWorkload] @DurationMinutes = 10;

-- Compare results
SELECT
    b.plan_id,
    b.avg_duration AS [BaselineDuration],
    c.avg_duration AS [CurrentDuration],
    CAST((c.avg_duration - b.avg_duration) * 100.0 / b.avg_duration AS DECIMAL(5,2)) AS [PercentChange]
FROM #Baseline b
INNER JOIN sys.query_store_runtime_stats c ON b.plan_id = c.plan_id;
```

### 3. sp_QuickieStore Comparison

```sql
-- Generate workload
EXEC [dbo].[Execute_ScaledWorkload] @DurationMinutes = 15;

-- Run sp_QuickieStore analysis
EXEC sp_QuickieStore @database_name = 'WorkloadTest';

-- Run QSAutomation analysis
EXEC QSAutomation.QueryStore_HighVariationCheck;

-- Compare findings
-- (See EXPERT_TOOL_COMPARISON_RESULTS.md for methodology)
```

## Tips and Best Practices

### Production Profiling

1. **Capture During Peak Hours** - Get representative workload
2. **Multiple Captures** - Different times/days for comprehensive view
3. **Document Context** - Note any special events (month-end, batch jobs)
4. **Reset Wait Stats First** (optional):
   ```sql
   -- Only if you want fresh snapshot
   DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
   -- Wait 15-30 minutes
   -- Then run profiling script
   ```

### Test Environment

1. **Match SQL Server Version** - Same version as production if possible
2. **Docker Recommended** - Easy to create/destroy test environments
3. **Query Store Settings** - Use short intervals (1 minute) for faster testing
4. **Workload Duration** - 10-15 minutes minimum for sufficient Query Store data

### Iterative Testing

```sql
-- Quick iteration cycle:

-- 1. Clear Query Store
ALTER DATABASE [WorkloadTest] SET QUERY_STORE CLEAR ALL;

-- 2. Make changes (install automation, tune thresholds, etc.)

-- 3. Run workload
EXEC [dbo].[Execute_ScaledWorkload] @DurationMinutes = 10;

-- 4. Analyze results
SELECT * FROM sys.query_store_query;

-- 5. Repeat
```

## Troubleshooting

### No Query Store Data Captured

**Problem:** Query Store shows 0 queries after workload

**Solutions:**
```sql
-- Check Query Store is actually enabled
SELECT
    [actual_state_desc],
    [readonly_reason],
    [current_storage_size_mb],
    [max_storage_size_mb]
FROM sys.database_query_store_options;

-- If not in READ_WRITE mode:
ALTER DATABASE [WorkloadTest] SET QUERY_STORE = ON;
ALTER DATABASE [WorkloadTest] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL  -- Make sure ALL queries captured
);

-- Check capture policy
ALTER DATABASE [WorkloadTest] SET QUERY_STORE (
    QUERY_CAPTURE_MODE = ALL,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000
);
```

### Workload Runs Too Fast

**Problem:** 15-minute workload finishes in 2 minutes

**Solution:** Adjust WAITFOR delay in Execute_ScaledWorkload
```sql
-- Edit the procedure, find:
WAITFOR DELAY '00:00:00.050'; -- 50ms

-- Increase delay:
WAITFOR DELAY '00:00:00.500'; -- 500ms for slower execution
```

### Not Enough Plan Variations

**Problem:** All queries have only 1 plan each

**Solution:** Force plan variations with hints
```sql
-- Add more hint variations to Workload_ParameterSniffing
-- Example: Execute same query with different hints

EXEC [dbo].[Workload_ParameterSniffing] @CategoryID = 5;
EXEC [dbo].[Workload_ParameterSniffing] @CategoryID = 5 WITH RECOMPILE;

-- Or add OPTION(OPTIMIZE FOR) variations
```

## Integration with QSAutomation Testing

Once you have a representative workload:

```sql
-- 1. Generate workload (creates Query Store data)
EXEC [dbo].[Execute_ScaledWorkload] @DurationMinutes = 15;

-- 2. Install QSAutomation schema
-- Run install_schema.sql from main repo

-- 3. Configure thresholds for testing
UPDATE QSAutomation.Configuration
SET ConfigurationValue = '10'  -- Lower for testing
WHERE ConfigurationName = 't-Statistic Threshold';

-- 4. Run automation
EXEC QSAutomation.QueryStore_HighVariationCheck;

-- 5. Review decisions
SELECT
    q.query_id,
    q.query_hash,
    q.Status,
    q.pinned_plan_id,
    q.t_Statistic,
    a.ActivityDescription
FROM QSAutomation.Query q
LEFT JOIN QSAutomation.ActivityLog a ON q.query_id = a.query_id
ORDER BY q.DateCreated DESC;
```

## Advanced: Multiple Profile Comparison

Track multiple production profiles:

```sql
-- Save profiles with timestamps
-- production_profile_20251225_morning.csv
-- production_profile_20251225_evening.csv
-- production_profile_20251225_monthend.csv

-- Create test scenarios for each
-- Compare how QSAutomation performs across different workload types
```

## Summary

This workload profiling approach gives you:

✓ **Realistic Testing** - Test data matches production characteristics
✓ **Scalable** - Works on any size test environment
✓ **Repeatable** - Consistent workload generation
✓ **Representative** - Same proportions as production
✓ **Fast Iteration** - Quick test cycles
✓ **Low Friction** - Easy capture and replay

The key insight: You don't need production-scale resources to test production-representative workloads. You just need the same **proportions and characteristics** scaled to your test environment.
