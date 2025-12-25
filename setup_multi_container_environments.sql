-- Multi-Container Environment Setup Script
-- Implementing systematic methodology across 5 specialized containers
-- Date: 2025-12-25

PRINT 'MULTI-CONTAINER TESTING ENVIRONMENT SETUP'
PRINT '=========================================='
PRINT 'Phase 1: Environment Initialization'
PRINT ''

-- Container 1: Production Simulation (Port 1533)
-- Purpose: Realistic business scenario testing with e-commerce simulation
PRINT 'Setting up Production Simulation Container (Port 1533)'
PRINT '======================================================'

USE master;
GO

-- Drop existing databases if they exist
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'EcommerceSimulation')
BEGIN
    ALTER DATABASE EcommerceSimulation SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EcommerceSimulation;
END
GO

-- Create production simulation database
CREATE DATABASE EcommerceSimulation;
GO

-- Configure Query Store for production-like conditions
ALTER DATABASE EcommerceSimulation SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    INTERVAL_LENGTH_MINUTES = 5,        -- Production typical
    DATA_FLUSH_INTERVAL_SECONDS = 900,  -- 15 minutes (production standard)
    MAX_STORAGE_SIZE_MB = 1000,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30)
);
GO

USE EcommerceSimulation;
GO

-- Create QSAutomation schema and configuration
CREATE SCHEMA QSAutomation;
GO

-- Configuration table with production-appropriate settings
CREATE TABLE QSAutomation.Configuration (
    ConfigurationID int PRIMARY KEY,
    ConfigurationName varchar(100),
    ConfigurationValue varchar(100)
);
GO

INSERT INTO QSAutomation.Configuration VALUES
(1, 'Database Name', 'EcommerceSimulation'),
(2, 'Environment Type', 'Production'),
(3, 'Business Criticality', 'High'),
(4, 't-Statistic Threshold', '100'),     -- Original broken threshold
(5, 'DF Threshold', '10'),
(6, 'High Variation Duration Threshold (MS)', '500'),
(7, 'Test Start Time', CONVERT(varchar(50), GETDATE())),
(8, 'Container Port', '1533');
GO

-- Create realistic e-commerce schema
CREATE TABLE Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,
    FirstName varchar(50),
    LastName varchar(50), 
    Email varchar(100),
    RegistrationDate datetime DEFAULT GETDATE(),
    LastActivityDate datetime,
    TotalOrders int DEFAULT 0
);
GO

CREATE TABLE Products (
    ProductID int IDENTITY(1,1) PRIMARY KEY,
    ProductName varchar(200),
    CategoryID int,
    Price decimal(10,2),
    StockQuantity int,
    LastUpdated datetime DEFAULT GETDATE()
);
GO

CREATE TABLE Orders (
    OrderID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int,
    OrderDate datetime DEFAULT GETDATE(),
    TotalAmount decimal(10,2),
    OrderStatus varchar(20),
    ProcessingTime datetime
);
GO

CREATE TABLE OrderDetails (
    OrderDetailID int IDENTITY(1,1) PRIMARY KEY,
    OrderID int,
    ProductID int,
    Quantity int,
    UnitPrice decimal(10,2)
);
GO

-- Create indexes for realistic plan variations
CREATE INDEX IX_Customers_Email ON Customers(Email);
CREATE INDEX IX_Customers_LastActivity ON Customers(LastActivityDate);
CREATE INDEX IX_Products_Category ON Products(CategoryID);
CREATE INDEX IX_Products_Price ON Products(Price);
CREATE INDEX IX_Orders_Customer ON Orders(CustomerID);
CREATE INDEX IX_Orders_Date ON Orders(OrderDate);
CREATE INDEX IX_OrderDetails_Order ON OrderDetails(OrderID);
CREATE INDEX IX_OrderDetails_Product ON OrderDetails(ProductID);
GO

-- Generate realistic test data for production simulation
PRINT 'Generating production simulation data...'

-- Insert realistic customer data
WITH CustomerGen AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1 FROM CustomerGen WHERE n < 10000
)
INSERT INTO Customers (FirstName, LastName, Email, RegistrationDate, LastActivityDate, TotalOrders)
SELECT 
    'Customer' + CAST(n AS varchar(10)),
    'Last' + CAST(n AS varchar(10)),
    'customer' + CAST(n AS varchar(10)) + '@email.com',
    DATEADD(day, -(n % 365), GETDATE()),
    DATEADD(hour, -(n % 24), GETDATE()),
    n % 50
FROM CustomerGen
OPTION (MAXRECURSION 10000);
GO

-- Insert product catalog
WITH ProductGen AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1 FROM ProductGen WHERE n < 5000
)
INSERT INTO Products (ProductName, CategoryID, Price, StockQuantity)
SELECT 
    'Product ' + CAST(n AS varchar(10)),
    (n % 20) + 1,
    (n % 1000) + 10.99,
    (n % 500) + 10
FROM ProductGen
OPTION (MAXRECURSION 5000);
GO

-- Insert realistic order history
WITH OrderGen AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1 FROM OrderGen WHERE n < 25000
)
INSERT INTO Orders (CustomerID, OrderDate, TotalAmount, OrderStatus)
SELECT 
    (n % 10000) + 1,
    DATEADD(hour, -(n % 8760), GETDATE()),
    (n % 500) + 25.00,
    CASE (n % 4) 
        WHEN 0 THEN 'Completed'
        WHEN 1 THEN 'Processing'
        WHEN 2 THEN 'Shipped'
        ELSE 'Cancelled'
    END
FROM OrderGen
OPTION (MAXRECURSION 25000);
GO

-- Insert order details
WITH DetailGen AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1 FROM DetailGen WHERE n < 50000
)
INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
SELECT 
    (n % 25000) + 1,
    (n % 5000) + 1,
    (n % 5) + 1,
    (n % 100) + 9.99
FROM DetailGen
OPTION (MAXRECURSION 50000);
GO

PRINT 'Production simulation environment setup complete.'
PRINT 'Data generated: 10K customers, 5K products, 25K orders, 50K order details'
PRINT ''

-- Create monitoring tables for test results
CREATE TABLE QSAutomation.TestResults (
    TestID int IDENTITY(1,1) PRIMARY KEY,
    TestName varchar(100),
    TestPhase varchar(50),
    TestScenario varchar(100),
    ExpectedOutcome varchar(200),
    ActualOutcome varchar(200),
    PerformanceMetrics varchar(500),
    BusinessImpact varchar(200),
    TestDate datetime DEFAULT GETDATE(),
    ContainerEnvironment varchar(50)
);
GO

CREATE TABLE QSAutomation.ThresholdTestResults (
    TestID int IDENTITY(1,1) PRIMARY KEY,
    Threshold float,
    PlansIdentified int,
    PlansForced int,
    EstimatedBusinessImpact money,
    FalsePositiveRisk float,
    TestDate datetime DEFAULT GETDATE(),
    ContainerEnvironment varchar(50)
);
GO

-- Create summary view for multi-container analysis
CREATE VIEW QSAutomation.MultiContainerSummary AS
SELECT 
    ContainerEnvironment,
    COUNT(*) as TotalTests,
    COUNT(CASE WHEN ActualOutcome LIKE '%SUCCESS%' THEN 1 END) as SuccessfulTests,
    COUNT(CASE WHEN ActualOutcome LIKE '%FAIL%' THEN 1 END) as FailedTests,
    AVG(CAST(SUBSTRING(PerformanceMetrics, 1, CHARINDEX('ms', PerformanceMetrics) - 1) AS float)) as AvgResponseTime
FROM QSAutomation.TestResults
GROUP BY ContainerEnvironment;
GO

PRINT 'Production simulation container setup completed successfully.'
PRINT 'Container ready for realistic e-commerce workload testing.'
GO