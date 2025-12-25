USE QSTest;
GO

-- Create QSAutomation schema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'QSAutomation')
BEGIN
	EXEC sp_ExecuteSQL N'CREATE SCHEMA QSAutomation'
END
GO

-- Create Status reference table
CREATE TABLE QSAutomation.[Status] (
	StatusID tinyint,
	StatusDescription VARCHAR(500)
);
GO

-- Create Query tracking table
CREATE TABLE QSAutomation.Query (
	QueryID bigint NOT NULL CONSTRAINT PK_Query PRIMARY KEY,
	QueryHash binary(8),
	StatusID tinyint,
	QueryCreationDatetime datetime2(2),
	QueryPlanID bigint NULL,
	PlanHash binary(8) NULL,
	PinDate datetime2(2) NULL
);
GO

-- Create Activity log table
CREATE TABLE QSAutomation.ActivityLog (
	ActivityLogID bigint NOT NULL IDENTITY(1,1) CONSTRAINT PK_ActivityLog PRIMARY KEY,
	ActivityDate datetime2(2),
	QueryID bigint NOT NULL,
	QueryPlanID bigint,
	ActionDetail nvarchar(max)
);
GO

-- Add default constraint
ALTER TABLE QSAutomation.ActivityLog ADD CONSTRAINT DF_ActivityLog_ActivityDate DEFAULT SYSDATETIME() FOR ActivityDate;
GO

-- Create Configuration table
CREATE TABLE QSAutomation.Configuration (
	ConfigurationID int,
	ConfigurationName varchar(100),
	ConfigurationValue varchar(100)
);
GO

-- Insert default configuration values
INSERT INTO QSAutomation.Configuration
VALUES (1, 'Query Unlock Start Time', NULL),
       (2, 'Last Query Store Reset', NULL),
       (3, 'Query Store Reset Count', '0'),
       (4, 't-Statistic Threshold', '100'),
       (5, 'DF Threshold', '10'),
       (6, 'High Variation Duration Threshold (MS)', '500'),
       (7, 'Mono Plan Performance Threshold (ms)', '2000'),
       (8, 'Notification Email Address', 'test@example.com'),
       (9, 'Email Log Level', 'Error');
GO

-- Insert status descriptions
INSERT INTO QSAutomation.[Status] 
VALUES (0, 'Never Unlocked'),
       (1, 'New query - pinned less than 1 day'),
       (2, 'Stage 1 - pinned less than 1 week'),
       (3, 'Stage 2 - pinned less than 3 weeks'),
       (4, 'Stage 3 - pinned less than 5 weeks'),
       (40, 'Stable plans');
GO

-- Verify installation
SELECT 'Schema created successfully' AS Result;
SELECT COUNT(*) AS ConfigurationRows FROM QSAutomation.Configuration;
SELECT COUNT(*) AS StatusRows FROM QSAutomation.[Status];
GO