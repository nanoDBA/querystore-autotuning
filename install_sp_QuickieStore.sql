-- Install sp_QuickieStore in our test environment
-- Source: https://github.com/erikdarlingdata/DarlingData
-- This will need to be downloaded from the GitHub repository

USE QSTest;
GO

-- Note: The actual sp_QuickieStore procedure code should be downloaded from:
-- https://raw.githubusercontent.com/erikdarlingdata/DarlingData/main/sp_QuickieStore/sp_QuickieStore.sql

-- After installation, we can use it to analyze our test data:

-- Example usage after installation:
/*
-- Get top 10 worst performing queries by CPU
EXEC sp_QuickieStore 
    @database_name = 'QSTest',
    @sort_order = 'cpu',
    @top = 10;

-- Get queries with high duration in last 24 hours
EXEC sp_QuickieStore 
    @database_name = 'QSTest', 
    @sort_order = 'duration',
    @start_date = DATEADD(day, -1, GETDATE()),
    @top = 20;

-- Compare with QSAutomation findings
EXEC QSAutomation.QueryStore_HighVariationCheck;
*/

PRINT 'sp_QuickieStore installation script prepared. Download from Erik Darling''s GitHub repo to complete installation.';
GO