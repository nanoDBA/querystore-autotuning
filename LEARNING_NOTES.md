# QueryStore Automation - Learning Notes

## Statistical Techniques Analysis

### 1. **High Variation Detection (Step 1)**

This procedure uses **two-sample t-statistics** to determine if the performance difference between the fastest and slowest execution plans is statistically significant.

#### Key Statistical Concepts:

**Pooled Standard Deviation Formula** (Lines 91-100):
```
PooledSD = SQRT(
    ((SD1² × (N1-1)) + (SD2² × (N2-1)))
    / (N1 + N2 - 2)
)
```

- Combines variance from both samples (fastest and slowest plans)
- Weights each sample's variance by its degrees of freedom (N-1)
- Used when comparing two samples with potentially different sample sizes

**t-Statistic Calculation** (Lines 87-106):
```
t = (Mean1 - Mean2) / (PooledSD × SQRT(1/N1 + 1/N2))
```

Where:
- Mean1, Mean2 = Average duration of slowest and fastest plans
- N1, N2 = Number of executions for each plan
- PooledSD = Pooled standard deviation across both samples

**Degrees of Freedom (DF)** (Lines 108-110):
```
DF = N1 + N2 - 2
```

#### Thresholds (from Configuration):
1. **t-Statistic Threshold**: Default = 100
   - Extremely conservative! Standard t-test critical values at 95% confidence:
     - DF=10: t ≈ 2.23
     - DF=30: t ≈ 2.04
     - DF=100: t ≈ 1.98
   - A threshold of 100 means they only pin plans with MASSIVE statistical significance
   - This prevents false positives and plan thrashing

2. **DF Threshold**: Default = 10
   - Requires sufficient sample size before making decisions
   - Ensures statistical power

3. **Duration Threshold**: Default = 500ms
   - Even if statistically significant, must have practical significance
   - Prevents optimizing queries where the gain is negligible

#### Why This Approach Works:

1. **Statistical Rigor**: Uses proper hypothesis testing
2. **Practical Significance**: Combines statistical AND absolute performance thresholds
3. **Robustness**: Pooled standard deviation handles different execution counts
4. **Conservative**: High t-statistic threshold prevents premature optimization

#### Key Insights from Lines 52-63:

**Weighted Average Duration**:
```sql
SUM(count_executions * avg_duration) / SUM(count_executions)
```
- Not just AVG(avg_duration) - weights by execution frequency
- More accurate representation of actual runtime behavior

**Pooled Standard Deviation Across Intervals**:
```sql
SQRT(SUM((count_executions - 1) * SQUARE(stdev_duration)) / SUM(count_executions - 1))
```
- Query Store tracks stats in intervals
- This pools variance across all intervals
- Proper statistical aggregation (not just AVG(stdev_duration))

**Execution Count Filtering**:
```sql
WHERE count_executions > 1 AND execution_type = 0
```
- Excludes single-execution intervals (no variance info)
- Only uses successful executions (type 0)
- Prevents divide-by-zero in variance calculations

---

## Plan Selection Logic

### Status States (0-40):
- **0**: Never Unlocked (manually selected plans)
- **1-4**: Staging levels over 5-week period
  - 1: New (< 1 day)
  - 2: Stage 1 (1-7 days)
  - 3: Stage 2 (1-3 weeks)
  - 4: Stage 3 (3-5 weeks)
- **11-14**: Temporarily unlocked variants (exploration mode)
- **20**: Mono-plan investigation
- **30**: Always unlocked (continuous search)
- **40**: Stable (graduated after 5 weeks)

### Plan Pinning Flow:
1. Identify queries with multiple plans
2. Calculate t-statistic for fastest vs slowest
3. If t > threshold AND duration delta > threshold AND DF > threshold:
   - Force fastest plan via `sp_query_store_force_plan`
   - Set status = 1 (new pin)
   - Log action to ActivityLog
4. Plan enters staged graduation process

---

## Testing Strategy

To properly test this system, we need to:

### 1. Create Plan Variation
- Queries that can generate multiple execution plans
- Parameter sniffing scenarios
- Index hint variations
- Statistics skew

### 2. Generate Sufficient Executions
- Need > DF threshold executions (default 10)
- Both fast and slow plans need multiple runs
- Execution type = 0 (successful)

### 3. Verify Statistical Calculations
- Manually calculate t-statistic for a test query
- Compare with procedure's decision
- Validate thresholds are working

### 4. Test Edge Cases
- Single-plan queries (should trigger mono-plan check)
- Invalid plans (should trigger cleanup)
- Manually pinned plans (should be enrolled)

---

## Questions to Investigate

1. Why t-statistic threshold of 100? (Industry standard is ~2-3)
   - ✅ CONFIRMED: Intentional "do no harm" production safety design
   - Essentially disables automation until DBAs manually identify problem queries
   - Prevents plan thrashing and business disruption
   - Designed for graduated deployment: install dormant → selective enabling → cautious expansion

2. How does Query Store interval aggregation affect accuracy?
   - Query Store uses time-based intervals (configurable)
   - Pooled stats across intervals is statistically correct
   - Need to test with different interval sizes

3. What happens during plan exploration (Status 11-14)?
   - Step 3 temporarily unpins plans
   - Tests if better plans have emerged
   - Need to trace this workflow

4. How does this handle parameter sniffing?
   - Multiple plans for same query_id
   - t-statistic compares average performance
   - Should favor the more universally good plan

---

## Next Steps

1. Set up SQL Server with Query Store enabled
2. Create schema (Step 0)
3. Install all stored procedures (Steps 1-8)
4. Generate test workload with known plan variations
5. Execute procedures and observe decisions
6. Manually verify statistical calculations
7. Test full lifecycle (pin → stage → unpin → repin)
8. Document actual behavior vs expected behavior

---

## Initial Observations

### Strengths:
- Proper statistical methodology
- Multiple safety thresholds
- Comprehensive logging
- Staged rollout approach
- Self-healing capabilities

### Potential Improvements:
- Could use Welch's t-test for unequal variances
- Could track confidence intervals
- Could implement A/B testing approach
- Could use Bayesian updating for faster convergence

### Production Readiness:
- MIT licensed, production-tested code
- Conservative defaults
- Good error handling
- Email notifications
- Audit trail

This is a well-designed system that uses sound statistical principles to automate query optimization!
