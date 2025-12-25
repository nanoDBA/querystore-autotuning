# QueryStore Testing Infrastructure Plan

**Date:** 2025-12-25
**Purpose:** Create comprehensive testing environment with realistic Query Store history

---

## 🎯 Testing Infrastructure Goals

### 1. **Integration with sp_QuickieStore**
- Use Erik Darling's sp_QuickieStore as baseline analysis tool
- Compare sp_QuickieStore findings vs QSAutomation decisions
- Validate that QSAutomation catches the same problem queries
- Use sp_QuickieStore to generate realistic test scenarios

### 2. **Query Store Backup/Restore Strategy**
- Create databases with pre-populated Query Store history
- Develop export/import procedures for Query Store data
- Build repeatable test scenarios with known baselines
- Enable regression testing of automation changes

---

## 📋 Implementation Plan

### Phase 1: sp_QuickieStore Integration

```sql
-- Download and install sp_QuickieStore
-- Compare its analysis with QSAutomation findings
-- Use its identified problem queries as test cases

-- Example integration:
EXEC sp_QuickieStore 
    @database_name = 'QSTest',
    @sort_order = 'cpu',
    @top = 20,
    @start_date = '2025-12-20',
    @end_date = '2025-12-25';

-- Then run QSAutomation on same data:
EXEC QSAutomation.QueryStore_HighVariationCheck;

-- Compare results
```

### Phase 2: Query Store Data Management

#### Option A: Database Backup/Restore Approach
```sql
-- 1. Create "golden" test databases with realistic workloads
-- 2. Let Query Store capture natural execution patterns  
-- 3. Backup entire database including Query Store data
-- 4. Restore for consistent test environments

BACKUP DATABASE QSTestGolden 
TO DISK = 'QSTestGolden_WithQueryStoreHistory.bak';

RESTORE DATABASE QSTest_Clean 
FROM DISK = 'QSTestGolden_WithQueryStoreHistory.bak';
```

#### Option B: Query Store Export/Import (Preferred)
```sql
-- Export Query Store data to staging tables
CREATE PROCEDURE QSTest.ExportQueryStoreData
AS
BEGIN
    -- Export sys.query_store_query
    SELECT * INTO QSBackup.query_store_query_backup 
    FROM sys.query_store_query;
    
    -- Export sys.query_store_plan  
    SELECT * INTO QSBackup.query_store_plan_backup
    FROM sys.query_store_plan;
    
    -- Export sys.query_store_runtime_stats
    SELECT * INTO QSBackup.query_store_runtime_stats_backup
    FROM sys.query_store_runtime_stats;
    
    -- Export other Query Store tables...
END;

-- Import for testing
CREATE PROCEDURE QSTest.ImportQueryStoreData
AS  
BEGIN
    -- Clear current Query Store
    ALTER DATABASE QSTest SET QUERY_STORE CLEAR;
    
    -- Complex procedure to rebuild Query Store from backups
    -- (Note: This is conceptual - actual implementation would be complex)
END;
```

### Phase 3: Realistic Test Database Creation

#### Test Database Profiles:

**Database 1: E-commerce Workload**
```sql
-- Characteristics:
-- - High transaction volume
-- - Parameter sniffing issues (customer-based queries)
-- - Seasonal patterns (holiday vs normal)  
-- - Index maintenance windows
-- Target scenarios: High variation queries, parameter sniffing
```

**Database 2: Reporting Workload**  
```sql
-- Characteristics:
-- - Long-running analytical queries
-- - Batch processing windows
-- - Data warehouse ETL patterns
-- Target scenarios: Mono-plan performance issues
```

**Database 3: Mixed OLTP Workload**
```sql
-- Characteristics:  
-- - Frequent small transactions
-- - Ad-hoc queries from applications
-- - Schema evolution (index changes)
-- Target scenarios: Plan regression, invalid plans
```

### Phase 4: Automated Test Scenarios

#### Scenario Generator Framework:
```sql
CREATE PROCEDURE QSTest.GenerateTestWorkload
    @WorkloadType varchar(20), -- 'ecommerce', 'reporting', 'oltp'
    @Duration int = 60,        -- minutes
    @Intensity int = 1         -- 1=light, 5=heavy
AS
BEGIN
    -- Execute realistic workload patterns
    -- Generate plan variations through:
    -- - Parameter value distributions  
    -- - Execution timing patterns
    -- - Resource contention simulation
    -- - Schema change simulation
END;
```

---

## 🔧 Integration with sp_QuickieStore

### Workflow Integration:
1. **Baseline Analysis:** Run sp_QuickieStore to identify current problems
2. **QSAutomation Analysis:** Run QSAutomation procedures  
3. **Comparison:** Validate overlap and differences
4. **Tuning:** Adjust QSAutomation thresholds based on sp_QuickieStore insights

### Comparative Analysis Framework:
```sql
-- Create analysis comparison procedure
CREATE PROCEDURE QSTest.CompareAnalysisTools
AS
BEGIN
    -- Get sp_QuickieStore top problem queries
    EXEC sp_QuickieStore @database_name = 'QSTest', @sort_order = 'cpu';
    
    -- Get QSAutomation recommendations
    EXEC QSAutomation.QueryStore_HighVariationCheck;
    
    -- Compare results:
    -- - Which queries both tools identify
    -- - Which queries only sp_QuickieStore finds
    -- - Which queries QSAutomation would optimize  
    -- - Effectiveness comparison
END;
```

---

## 📈 Expected Benefits

### 1. **Realistic Testing**
- Test with actual production-like Query Store data
- Validate automation decisions against expert analysis
- Build confidence in threshold tuning

### 2. **Expert Validation**  
- Erik Darling's sp_QuickieStore represents expert knowledge
- Use as benchmark for automation quality
- Learn from community best practices

### 3. **Repeatable Tests**
- Consistent baseline for regression testing
- A/B testing of different threshold configurations
- Performance benchmarking over time

### 4. **Production Readiness**
- Test automation with realistic workload patterns
- Validate safety mechanisms under stress
- Build operational confidence

---

## 🚀 Next Steps

1. **Download and install sp_QuickieStore** in test environment
2. **Create test database with realistic workload** 
3. **Generate Query Store history** through extended execution
4. **Implement backup/restore methodology**
5. **Build comparative analysis procedures**
6. **Document findings** and threshold recommendations

This infrastructure will provide the foundation for thorough, realistic testing of the QSAutomation system against industry-standard analysis tools.