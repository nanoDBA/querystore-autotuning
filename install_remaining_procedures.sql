USE QSTest;
GO

-- Install remaining QSAutomation procedures for comprehensive testing
PRINT 'Installing QSAutomation Steps 2-8...'
PRINT '===================================='
GO

-- We need to copy the actual procedure content from the original files
-- For now, let's create simplified test versions to validate the framework

-- Step 2: Invalid Plan Check (already installed, let's verify)
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_InvalidPlanCheck' AND schema_id = SCHEMA_ID('QSAutomation'))
    PRINT 'Step 2 (Invalid Plan Check) - Already installed ✓'
ELSE
    PRINT 'Step 2 (Invalid Plan Check) - MISSING! Need to install.'
GO

-- Create a comprehensive test framework for all procedures
CREATE OR ALTER PROCEDURE QSTest.TestAllProcedures
AS
BEGIN
    PRINT 'Testing all QSAutomation procedures...'
    
    -- Test Step 1: High Variation Check
    PRINT 'Testing Step 1: High Variation Check'
    BEGIN TRY
        EXEC QSAutomation.QueryStore_HighVariationCheck
        PRINT '✓ Step 1 executed successfully'
    END TRY
    BEGIN CATCH
        PRINT '✗ Step 1 failed: ' + ERROR_MESSAGE()
    END CATCH
    
    -- Test Step 2: Invalid Plan Check  
    PRINT 'Testing Step 2: Invalid Plan Check'
    BEGIN TRY
        EXEC QSAutomation.QueryStore_InvalidPlanCheck
        PRINT '✓ Step 2 executed successfully'
    END TRY
    BEGIN CATCH
        PRINT '✗ Step 2 failed: ' + ERROR_MESSAGE()
    END CATCH
    
    -- For Steps 3-8, we need to install them from the original files
    PRINT 'Steps 3-8 require installation from original source files'
    PRINT 'Checking for existing procedures...'
    
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_BetterPlanCheck' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 3 (Better Plan Check) installed'
    ELSE  
        PRINT '⚠ Step 3 (Better Plan Check) not installed'
        
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_ClearPlansFromCache' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 4 (Clear Plans From Cache) installed'
    ELSE
        PRINT '⚠ Step 4 (Clear Plans From Cache) not installed'
        
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_PoorPerformingMonoPlanCheck' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 5 (Poor Performing Mono-Plan Check) installed'
    ELSE
        PRINT '⚠ Step 5 (Poor Performing Mono-Plan Check) not installed'
        
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_FixBrokenQueryStore' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 6 (Fix Broken Query Store) installed'  
    ELSE
        PRINT '⚠ Step 6 (Fix Broken Query Store) not installed'
        
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_IncludeManuallyPinnedPlans' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 7 (Include Manually Pinned Plans) installed'
    ELSE
        PRINT '⚠ Step 7 (Include Manually Pinned Plans) not installed'
        
    IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'QueryStore_CleanupUnusedPlans' AND schema_id = SCHEMA_ID('QSAutomation'))
        PRINT '✓ Step 8 (Cleanup Unused Plans) installed'
    ELSE
        PRINT '⚠ Step 8 (Cleanup Unused Plans) not installed'
END
GO

-- Execute the test
EXEC QSTest.TestAllProcedures;
GO

-- Show current system state
PRINT 'Current QSAutomation system state:'
SELECT 'QSAutomation Procedures Installed' as Info, COUNT(*) as ProcedureCount
FROM sys.procedures 
WHERE schema_id = SCHEMA_ID('QSAutomation');

SELECT 'QSAutomation Tables Available' as Info, COUNT(*) as TableCount  
FROM sys.tables
WHERE schema_id = SCHEMA_ID('QSAutomation');

SELECT 'Configuration Settings' as Info, COUNT(*) as ConfigCount
FROM QSAutomation.Configuration;

SELECT 'Tracked Queries' as Info, COUNT(*) as TrackedCount
FROM QSAutomation.Query;

SELECT 'Activity Log Entries' as Info, COUNT(*) as LogEntries
FROM QSAutomation.ActivityLog;
GO