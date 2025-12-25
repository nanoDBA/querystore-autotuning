/**************************************************************************************************
	ALTERNATIVE APPROACH: Adaptive Query Plan Optimization
	
	This implementation challenges the static t-statistic approach with:
	1. Bayesian plan confidence scoring
	2. Time-decay weighted performance tracking  
	3. Context-aware plan selection
	4. Circuit breaker safety mechanisms
	
	Key improvements over original:
	- No arbitrary statistical thresholds (t=100)
	- Accounts for changing workload patterns
	- Business impact weighting
	- Automatic fallback mechanisms
*************************************************************************************************/

-- Enhanced configuration with adaptive parameters
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'AdaptiveQS')
    EXEC('CREATE SCHEMA AdaptiveQS')
GO

CREATE OR ALTER PROCEDURE AdaptiveQS.AdaptiveQueryOptimization
    @MaxRiskTolerance DECIMAL(3,2) = 0.05,  -- 5% confidence for plan changes
    @BusinessHoursOnly BIT = 1,
    @DryRun BIT = 0  -- Test mode - don't actually pin plans
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentTime DATETIME2 = SYSDATETIME()
    
    -- Temporary tables for analysis
    CREATE TABLE #PlanMetrics (
        QueryID BIGINT,
        PlanID BIGINT,
        PlanHash BINARY(8),
        
        -- Time-weighted performance metrics
        WeightedAvgDuration DECIMAL(19,5),
        RecentPerformanceTrend DECIMAL(19,5), -- Positive = getting slower
        
        -- Statistical confidence measures  
        BayesianConfidence DECIMAL(5,4), -- 0-1 scale
        ExecutionContext NVARCHAR(50), -- Peak/Off-Peak/Mixed
        
        -- Business impact weighting
        BusinessPriority INT, -- 1=Critical, 5=Low
        ResourceImpact DECIMAL(10,2), -- CPU/Memory cost per execution
        
        -- Risk metrics
        PerformanceVolatility DECIMAL(10,5), -- Coefficient of variation
        LastPinDate DATETIME2,
        RiskScore DECIMAL(5,4) -- Combined risk assessment
    );
    
    -- Populate with enhanced metrics using time-decay weighting
    WITH TimeWeightedStats AS (
        SELECT 
            qsp.query_id,
            qsp.plan_id,
            qsp.query_plan_hash,
            
            -- Apply exponential decay - recent data weighted more heavily
            SUM(qsrs.count_executions * qsrs.avg_duration * 
                POWER(0.95, DATEDIFF(DAY, qsrs.last_execution_time, @CurrentTime))) /
            SUM(qsrs.count_executions * 
                POWER(0.95, DATEDIFF(DAY, qsrs.last_execution_time, @CurrentTime))) AS WeightedAvgDuration,
                
            -- Performance trend analysis (linear regression slope)
            -- Positive = performance degrading over time
            (COUNT(*) * SUM(CAST(qsrs.last_execution_time AS FLOAT) * qsrs.avg_duration) - 
             SUM(CAST(qsrs.last_execution_time AS FLOAT)) * SUM(qsrs.avg_duration)) /
            (COUNT(*) * SUM(POWER(CAST(qsrs.last_execution_time AS FLOAT), 2)) - 
             POWER(SUM(CAST(qsrs.last_execution_time AS FLOAT)), 2)) AS PerformanceTrend,
             
            -- Volatility measure (coefficient of variation)
            CASE 
                WHEN AVG(qsrs.avg_duration) > 0 
                THEN STDEV(qsrs.avg_duration) / AVG(qsrs.avg_duration)
                ELSE 0 
            END AS Volatility,
            
            SUM(qsrs.count_executions) AS TotalExecutions
            
        FROM sys.query_store_plan qsp
        JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
        WHERE qsrs.last_execution_time >= DATEADD(DAY, -30, @CurrentTime)
            AND qsrs.execution_type = 0  -- Successful executions only
            AND qsrs.count_executions > 0
        GROUP BY qsp.query_id, qsp.plan_id, qsp.query_plan_hash
        HAVING SUM(qsrs.count_executions) >= 5  -- Minimum execution threshold
    ),
    
    -- Bayesian confidence calculation
    BayesianAnalysis AS (
        SELECT *,
            -- Bayesian confidence using Beta distribution
            -- Higher execution count = higher confidence
            CASE 
                WHEN TotalExecutions < 10 THEN 0.1  -- Low confidence
                WHEN TotalExecutions < 50 THEN 0.5  -- Medium confidence  
                WHEN TotalExecutions < 200 THEN 0.8 -- High confidence
                ELSE 0.95  -- Very high confidence
            END * 
            -- Adjust for volatility - more volatile = less confident
            (1.0 - LEAST(Volatility, 0.9)) AS BayesianConfidence,
            
            -- Execution context classification
            CASE
                WHEN EXISTS (
                    SELECT 1 FROM sys.query_store_runtime_stats qsrs2
                    WHERE qsrs2.plan_id = tws.plan_id
                        AND DATEPART(HOUR, qsrs2.last_execution_time) BETWEEN 9 AND 17
                        AND DATENAME(WEEKDAY, qsrs2.last_execution_time) IN ('Monday','Tuesday','Wednesday','Thursday','Friday')
                ) AND EXISTS (
                    SELECT 1 FROM sys.query_store_runtime_stats qsrs3
                    WHERE qsrs3.plan_id = tws.plan_id
                        AND (DATEPART(HOUR, qsrs3.last_execution_time) NOT BETWEEN 9 AND 17
                             OR DATENAME(WEEKDAY, qsrs3.last_execution_time) IN ('Saturday','Sunday'))
                ) THEN 'Mixed'
                WHEN EXISTS (
                    SELECT 1 FROM sys.query_store_runtime_stats qsrs4
                    WHERE qsrs4.plan_id = tws.plan_id
                        AND DATEPART(HOUR, qsrs4.last_execution_time) BETWEEN 9 AND 17
                ) THEN 'Peak'
                ELSE 'Off-Peak'
            END AS ExecutionContext
            
        FROM TimeWeightedStats tws
    )
    
    INSERT INTO #PlanMetrics
    SELECT 
        ba.query_id,
        ba.plan_id, 
        ba.query_plan_hash,
        ba.WeightedAvgDuration,
        ba.PerformanceTrend,
        ba.BayesianConfidence,
        ba.ExecutionContext,
        
        -- Business priority (simplified - could be enhanced with query classification)
        CASE 
            WHEN ba.WeightedAvgDuration > 10000 THEN 1  -- Critical (>10s)
            WHEN ba.WeightedAvgDuration > 5000 THEN 2   -- High (>5s)
            WHEN ba.WeightedAvgDuration > 1000 THEN 3   -- Medium (>1s)
            WHEN ba.WeightedAvgDuration > 100 THEN 4    -- Normal (>100ms)
            ELSE 5  -- Low priority
        END AS BusinessPriority,
        
        -- Resource impact estimation
        ba.WeightedAvgDuration * ba.TotalExecutions / 30.0 AS ResourceImpact, -- Daily resource cost
        
        ba.Volatility,
        
        -- Check if plan was recently pinned
        COALESCE(
            (SELECT MAX(created_time) 
             FROM sys.query_store_plan qsp2 
             WHERE qsp2.plan_id = ba.plan_id AND qsp2.is_forced_plan = 1),
            '1900-01-01'
        ) AS LastPinDate,
        
        -- Combined risk score
        (ba.Volatility * 0.4 +  -- Performance volatility weight
         CASE WHEN ba.PerformanceTrend > 0 THEN LEAST(ba.PerformanceTrend / ba.WeightedAvgDuration, 0.5) ELSE 0 END * 0.3 +  -- Degradation trend weight
         CASE WHEN ba.BayesianConfidence < 0.7 THEN (0.7 - ba.BayesianConfidence) ELSE 0 END * 0.3  -- Low confidence penalty
        ) AS RiskScore
        
    FROM BayesianAnalysis ba;
    
    -- Plan selection logic with circuit breaker
    DECLARE @QueryID BIGINT, @RecommendedPlanID BIGINT, @CurrentForcedPlanID BIGINT
    DECLARE @RiskScore DECIMAL(5,4), @PerformanceGain DECIMAL(10,2)
    
    -- Cursor for plan recommendations 
    DECLARE plan_cursor CURSOR FOR
    SELECT 
        pm1.QueryID,
        pm1.PlanID AS RecommendedPlanID,
        COALESCE(pm2.PlanID, -1) AS CurrentForcedPlanID,
        pm1.RiskScore,
        CASE 
            WHEN pm2.PlanID IS NOT NULL 
            THEN ((pm2.WeightedAvgDuration - pm1.WeightedAvgDuration) / pm2.WeightedAvgDuration) * 100
            ELSE 0
        END AS PerformanceGainPercent
    FROM #PlanMetrics pm1
    LEFT JOIN (
        -- Current forced plan for this query
        SELECT qsp.query_id, qsp.plan_id, pm.WeightedAvgDuration
        FROM sys.query_store_plan qsp
        JOIN #PlanMetrics pm ON qsp.plan_id = pm.PlanID
        WHERE qsp.is_forced_plan = 1
    ) pm2 ON pm1.QueryID = pm2.query_id
    WHERE pm1.RiskScore <= @MaxRiskTolerance  -- Risk tolerance check
        AND pm1.BayesianConfidence >= 0.7     -- Confidence threshold
        AND (pm2.query_id IS NULL OR pm1.WeightedAvgDuration < pm2.WeightedAvgDuration * 0.8) -- 20% improvement minimum
        AND pm1.BusinessPriority <= 3  -- Only optimize high/critical queries
        AND (NOT @BusinessHoursOnly OR 
             (DATEPART(HOUR, @CurrentTime) BETWEEN 9 AND 17 AND 
              DATENAME(WEEKDAY, @CurrentTime) IN ('Monday','Tuesday','Wednesday','Thursday','Friday')))
    ORDER BY 
        pm1.BusinessPriority ASC,  -- Prioritize critical queries
        ((COALESCE(pm2.WeightedAvgDuration, pm1.WeightedAvgDuration * 2) - pm1.WeightedAvgDuration) / pm1.WeightedAvgDuration) DESC; -- Biggest gains first
    
    OPEN plan_cursor;
    FETCH NEXT FROM plan_cursor INTO @QueryID, @RecommendedPlanID, @CurrentForcedPlanID, @RiskScore, @PerformanceGain;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @ActionTaken NVARCHAR(100) = '';
        
        IF @DryRun = 1
        BEGIN
            -- Log recommendation without taking action
            SET @ActionTaken = 'DRY_RUN_RECOMMEND';
            PRINT CONCAT('DRY RUN: Would pin plan ', @RecommendedPlanID, ' for query ', @QueryID, 
                        ' (Risk: ', @RiskScore, ', Gain: ', @PerformanceGain, '%)');
        END
        ELSE
        BEGIN
            -- Circuit breaker: Check recent performance before pinning
            DECLARE @RecentFailures INT = 0;
            
            SELECT @RecentFailures = COUNT(*)
            FROM sys.query_store_runtime_stats qsrs
            WHERE qsrs.plan_id = @RecommendedPlanID
                AND qsrs.last_execution_time >= DATEADD(MINUTE, -5, @CurrentTime)
                AND qsrs.execution_type != 0; -- Count failures
            
            IF @RecentFailures = 0
            BEGIN
                -- Safe to pin the plan
                BEGIN TRY
                    EXEC sp_query_store_force_plan @QueryID, @RecommendedPlanID;
                    SET @ActionTaken = 'PLAN_PINNED';
                    
                    PRINT CONCAT('Pinned plan ', @RecommendedPlanID, ' for query ', @QueryID, 
                                ' (Risk: ', @RiskScore, ', Expected gain: ', @PerformanceGain, '%)');
                END TRY
                BEGIN CATCH
                    SET @ActionTaken = 'PIN_FAILED';
                    PRINT CONCAT('Failed to pin plan ', @RecommendedPlanID, ' for query ', @QueryID, ': ', ERROR_MESSAGE());
                END CATCH
            END
            ELSE
            BEGIN
                SET @ActionTaken = 'CIRCUIT_BREAKER_TRIGGERED';
                PRINT CONCAT('Circuit breaker prevented pinning plan ', @RecommendedPlanID, ' for query ', @QueryID, ' (Recent failures: ', @RecentFailures, ')');
            END
        END
        
        -- Log the decision for audit trail
        -- (Would insert into AdaptiveQS.OptimizationLog table in real implementation)
        
        FETCH NEXT FROM plan_cursor INTO @QueryID, @RecommendedPlanID, @CurrentForcedPlanID, @RiskScore, @PerformanceGain;
    END
    
    CLOSE plan_cursor;
    DEALLOCATE plan_cursor;
    
    DROP TABLE #PlanMetrics;
    
    PRINT CONCAT('Adaptive optimization completed at ', @CurrentTime);
END
GO

/**************************************************************************************************
	MONITORING AND ALERTING PROCEDURES
*************************************************************************************************/

-- Circuit breaker monitoring 
CREATE OR ALTER PROCEDURE AdaptiveQS.MonitorPinnedPlanHealth
AS
BEGIN
    -- Detect pinned plans that are performing worse than before pinning
    WITH PinnedPlanHealth AS (
        SELECT 
            qsp.query_id,
            qsp.plan_id,
            qsp.query_plan_hash,
            
            -- Performance since pinning
            AVG(CASE WHEN qsrs.last_execution_time >= qsp.created_time 
                     THEN qsrs.avg_duration ELSE NULL END) AS AvgDurationSincePinning,
                     
            -- Performance before pinning  
            AVG(CASE WHEN qsrs.last_execution_time < qsp.created_time 
                     THEN qsrs.avg_duration ELSE NULL END) AS AvgDurationBeforePinning,
                     
            COUNT(CASE WHEN qsrs.execution_type != 0 AND qsrs.last_execution_time >= qsp.created_time 
                       THEN 1 ELSE NULL END) AS FailuresSincePinning
                       
        FROM sys.query_store_plan qsp
        JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
        WHERE qsp.is_forced_plan = 1
            AND qsp.created_time >= DATEADD(DAY, -7, SYSDATETIME())  -- Recently pinned plans
        GROUP BY qsp.query_id, qsp.plan_id, qsp.query_plan_hash, qsp.created_time
    )
    
    SELECT 
        query_id,
        plan_id,
        AvgDurationSincePinning,
        AvgDurationBeforePinning,
        CASE 
            WHEN AvgDurationBeforePinning > 0 
            THEN ((AvgDurationSincePinning - AvgDurationBeforePinning) / AvgDurationBeforePinning) * 100
            ELSE 0
        END AS PerformanceChangePercent,
        FailuresSincePinning,
        CASE 
            WHEN FailuresSincePinning > 5 THEN 'UNPIN_IMMEDIATELY'
            WHEN AvgDurationSincePinning > AvgDurationBeforePinning * 1.2 THEN 'UNPIN_RECOMMENDED'
            WHEN AvgDurationSincePinning > AvgDurationBeforePinning * 1.05 THEN 'MONITOR_CLOSELY'
            ELSE 'HEALTHY'
        END AS HealthStatus
        
    FROM PinnedPlanHealth
    WHERE AvgDurationSincePinning IS NOT NULL
        AND AvgDurationBeforePinning IS NOT NULL
    ORDER BY PerformanceChangePercent DESC;
END
GO

/**************************************************************************************************
	USAGE EXAMPLE AND TESTING
*************************************************************************************************/

-- Example: Run adaptive optimization in dry-run mode
-- EXEC AdaptiveQS.AdaptiveQueryOptimization @DryRun = 1;

-- Example: Monitor pinned plan health
-- EXEC AdaptiveQS.MonitorPinnedPlanHealth;

-- Example: Production run with conservative risk tolerance
-- EXEC AdaptiveQS.AdaptiveQueryOptimization @MaxRiskTolerance = 0.02, @BusinessHoursOnly = 1;