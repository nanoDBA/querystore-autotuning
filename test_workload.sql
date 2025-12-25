--**************************************************************************************************
-- Test Workload: Generate Multiple Execution Plans for Query Store Testing
--**************************************************************************************************

USE QSAutomationTest;
GO

-- Create test table with skewed data distribution
DROP TABLE IF EXISTS dbo.Orders;
GO

CREATE TABLE dbo.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    OrderAmount DECIMAL(10,2) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

CREATE INDEX IX_Orders_CustomerID ON dbo.Orders(CustomerID) INCLUDE (OrderAmount, Status);
CREATE INDEX IX_Orders_Status ON dbo.Orders(Status) INCLUDE (OrderAmount);
GO

-- Insert data with HIGHLY skewed distribution
-- CustomerID 1: 95% of records (95,000 rows) - "bad" for seek
-- CustomerID 2-100: 5% of records (5,000 rows total) - "good" for seek

DECLARE @i INT = 1;
WHILE @i <= 95000
BEGIN
    INSERT INTO dbo.Orders (CustomerID, OrderDate, OrderAmount, Status)
    VALUES (1, DATEADD(DAY, -@i % 365, GETDATE()), (@i % 1000) + 10.00,
            CASE WHEN @i % 3 = 0 THEN 'Completed' ELSE 'Pending' END);
    SET @i = @i + 1;
END

SET @i = 1;
WHILE @i <= 5000
BEGIN
    INSERT INTO dbo.Orders (CustomerID, OrderDate, OrderAmount, Status)
    VALUES ((@i % 99) + 2, DATEADD(DAY, -@i % 365, GETDATE()), (@i % 500) + 5.00,
            CASE WHEN @i % 2 = 0 THEN 'Completed' ELSE 'Shipped' END);
    SET @i = @i + 1;
END
GO

UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
GO

-- Create a procedure that will exhibit parameter sniffing
DROP PROCEDURE IF EXISTS dbo.GetCustomerOrders;
GO

CREATE PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- This query will get different plans based on @CustomerID
    SELECT
        o.OrderID,
        o.CustomerID,
        o.OrderDate,
        o.OrderAmount,
        o.Status
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
        AND o.Status IN ('Completed', 'Shipped', 'Pending')
    ORDER BY o.OrderDate DESC;
END
GO

PRINT 'Test schema created successfully';
PRINT 'CustomerID 1: ~95,000 rows (should favor scan)';
PRINT 'CustomerID 2-100: ~50 rows each (should favor seek)';
GO
