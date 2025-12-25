-- Create test database and enable Query Store
CREATE DATABASE QSTest;
GO

-- Enable Query Store with short intervals for testing
ALTER DATABASE QSTest SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    INTERVAL_LENGTH_MINUTES = 1,
    DATA_FLUSH_INTERVAL_SECONDS = 60
);
GO

USE QSTest;
GO

-- Verify Query Store is enabled
SELECT 
    name,
    is_query_store_on,
    query_store_options
FROM sys.databases 
WHERE name = 'QSTest';
GO