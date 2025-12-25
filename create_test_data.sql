USE QSTest;
GO

-- Create test table with data that will generate different plans
CREATE TABLE Orders (
    OrderID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID varchar(10),
    OrderDate datetime,
    Amount decimal(10,2),
    Status varchar(20)
);
GO

-- Create index that will be used for some plans but not others
CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
CREATE INDEX IX_Orders_OrderDate ON Orders(OrderDate);
GO

-- Insert test data - mix of high and low cardinality customers
DECLARE @i int = 1;
WHILE @i <= 10000
BEGIN
    INSERT INTO Orders (CustomerID, OrderDate, Amount, Status)
    VALUES (
        CASE 
            WHEN @i <= 100 THEN 'WHALE001'  -- High cardinality customer (100 orders)
            WHEN @i <= 200 THEN 'WHALE002'  -- High cardinality customer (100 orders)
            ELSE 'CUST' + CAST((@i % 1000) AS varchar(10))  -- Low cardinality customers (1-10 orders each)
        END,
        DATEADD(day, -(@i % 365), GETDATE()),
        RAND() * 1000,
        CASE WHEN @i % 4 = 0 THEN 'COMPLETED' ELSE 'PENDING' END
    );
    SET @i = @i + 1;
END;
GO

-- Update statistics
UPDATE STATISTICS Orders;
GO

-- Verify data distribution
SELECT 'Data created successfully' AS Result;
SELECT CustomerID, COUNT(*) as OrderCount 
FROM Orders 
GROUP BY CustomerID 
HAVING COUNT(*) > 10 
ORDER BY OrderCount DESC;
GO