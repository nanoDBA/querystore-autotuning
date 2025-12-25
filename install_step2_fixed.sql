USE QSTest;
GO

/**************************************************************************************************
	Step 2:  Check for invalid plans
 *************************************************************************************************/
CREATE OR ALTER PROCEDURE QSAutomation.QueryStore_InvalidPlanCheck
AS
BEGIN
	DECLARE @QueryID bigint
		, @PlanID bigint
		, @DynamicSQL nvarchar(max)
		, @BodyText nvarchar(max)
		, @QueryText nvarchar(max)
		, @SubjectText nvarchar(max)
		, @FailureReason nvarchar(max)
		, @NotificationEmailAddress varchar(max)
		, @EmailLogLevel varchar(max)

	SELECT @NotificationEmailAddress = ConfigurationValue
	FROM QSAutomation.Configuration
	WHERE ConfigurationName = 'Notification Email Address'

	SELECT @EmailLogLevel = ConfigurationValue
	FROM QSAutomation.Configuration
	WHERE ConfigurationName = 'Email Log Level'

	--Step 1:  Pinned plans that are now invalid
	DECLARE InvalidPlans CURSOR FAST_FORWARD FOR
		SELECT TOP 1 query_id, plan_id, last_force_failure_reason_desc
		FROM sys.query_store_plan
		WHERE is_forced_plan = 1
			AND last_force_failure_reason != 0

	OPEN InvalidPlans
	FETCH NEXT FROM InvalidPlans INTO @QueryID, @PlanID, @FailureReason

	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC sp_query_store_unforce_plan @QueryID, @PlanID

		SELECT @QueryText = query_sql_text
		FROM sys.query_store_query_text qst
			INNER JOIN sys.query_store_query qs ON qst.query_text_id = qs.query_text_id
		WHERE qs.query_id = @QueryID

		INSERT INTO QSAutomation.ActivityLog (QueryID, QueryPlanID, ActionDetail)
		VALUES (@QueryID, @PlanID, 'Plan unpinned due to invalid plan failure: ' + @FailureReason)

		DELETE FROM QSAutomation.Query WHERE QueryID = @QueryID

		SET @SubjectText = 'Query Store Automation:  Plan Failure'
		SET @BodyText = 'Plan ID ' + CAST(@PlanID AS varchar(20)) + ' for Query ID ' + CAST(@QueryID AS varchar(20)) + ' has been unpinned due to: ' + @FailureReason + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) + 'Query Text: ' + ISNULL(@QueryText, 'NULL')

		-- Email notification would go here in production
		PRINT 'NOTIFICATION: ' + @SubjectText + ' - ' + @BodyText

		FETCH NEXT FROM InvalidPlans INTO @QueryID, @PlanID, @FailureReason
	END

	CLOSE InvalidPlans
	DEALLOCATE InvalidPlans

END
GO