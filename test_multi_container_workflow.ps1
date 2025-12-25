# =============================================
# Multi-Container Testing Workflow
# =============================================
# Purpose: Test diagnostic workflow across multiple SQL Server containers
# with different configurations and workload characteristics
# =============================================

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Multi-Container Testing Workflow" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$Password = "TestPass123!"
$BasePort = 1433
$ResultsDir = "G:\My Drive\backups\repos\querystore-autotuning\test_results"

# Create results directory
if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir | Out-Null
    Write-Host "Created results directory: $ResultsDir" -ForegroundColor Green
}

# Define container configurations
$Containers = @(
    @{
        Name = "sqltest-small"
        Port = 1433
        CPUs = "1"
        Memory = "2g"
        Description = "Small single-core container"
        WorkloadType = "MIXED_WORKLOAD"
    },
    @{
        Name = "sqltest-medium"
        Port = 1434
        CPUs = "2"
        Memory = "4g"
        Description = "Medium dual-core container"
        WorkloadType = "CPU_INTENSIVE"
    },
    @{
        Name = "sqltest-large"
        Port = 1435
        CPUs = "4"
        Memory = "8g"
        Description = "Large quad-core container"
        WorkloadType = "IO_INTENSIVE"
    }
)

# =============================================
# Function: Cleanup Container
# =============================================
function Remove-TestContainer {
    param($ContainerName)

    Write-Host "Cleaning up container: $ContainerName" -ForegroundColor Yellow

    $existing = docker ps -a --filter "name=$ContainerName" --format "{{.Names}}"
    if ($existing -eq $ContainerName) {
        docker stop $ContainerName 2>&1 | Out-Null
        docker rm $ContainerName 2>&1 | Out-Null
        Write-Host "  Removed existing container: $ContainerName" -ForegroundColor Green
    }
}

# =============================================
# Function: Create Container
# =============================================
function New-TestContainer {
    param(
        $Name,
        $Port,
        $CPUs,
        $Memory
    )

    Write-Host "Creating container: $Name" -ForegroundColor Cyan
    Write-Host "  Port: $Port, CPUs: $CPUs, Memory: $Memory" -ForegroundColor Gray

    $result = docker run -d `
        --name $Name `
        --cpus $CPUs `
        --memory $Memory `
        -e "ACCEPT_EULA=Y" `
        -e "MSSQL_SA_PASSWORD=$Password" `
        -p "${Port}:1433" `
        mcr.microsoft.com/mssql/server:2022-latest

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Container created: $Name" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  Failed to create container: $Name" -ForegroundColor Red
        return $false
    }
}

# =============================================
# Function: Wait for SQL Server
# =============================================
function Wait-SqlServer {
    param($Port, $MaxWaitSeconds = 60)

    Write-Host "  Waiting for SQL Server on port $Port..." -ForegroundColor Gray

    $elapsed = 0
    $interval = 5

    while ($elapsed -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        $result = sqlcmd -S "localhost,$Port" -U sa -P $Password -Q "SELECT 1" -h -1 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  SQL Server ready on port $Port" -ForegroundColor Green
            return $true
        }

        Write-Host "  Still waiting... ($elapsed seconds)" -ForegroundColor Gray
    }

    Write-Host "  Timeout waiting for SQL Server on port $Port" -ForegroundColor Red
    return $false
}

# =============================================
# Function: Run Diagnostic Profile
# =============================================
function Invoke-DiagnosticProfile {
    param(
        $Port,
        $ContainerName
    )

    Write-Host "Running diagnostic profile on port $Port..." -ForegroundColor Cyan

    $outputFile = Join-Path $ResultsDir "${ContainerName}_profile.txt"

    # Run the workload profile helper
    $result = sqlcmd -S "localhost,$Port" -U sa -P $Password `
        -i "G:\My Drive\backups\repos\querystore-autotuning\workload_profile_helper.sql" `
        -o $outputFile `
        -y 0

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Profile saved to: $outputFile" -ForegroundColor Green
        return $outputFile
    } else {
        Write-Host "  Failed to run diagnostic profile" -ForegroundColor Red
        return $null
    }
}

# =============================================
# Function: Generate Test Workload
# =============================================
function New-TestWorkload {
    param(
        $Port,
        $ContainerName,
        $ReadPct = 75,
        $WritePct = 25
    )

    Write-Host "Generating test workload on port $Port..." -ForegroundColor Cyan

    # Create a temporary script with the workload profile
    $scriptPath = Join-Path $ResultsDir "${ContainerName}_workload_setup.sql"

    # Read the template
    $template = Get-Content "G:\My Drive\backups\repos\querystore-autotuning\generate_scaled_test_workload.sql" -Raw

    # For now, just run it as-is (in production, we'd parse the profile and inject values)
    $template | Out-File -FilePath $scriptPath -Encoding UTF8

    # Execute the workload setup
    Write-Host "  Setting up workload database..." -ForegroundColor Gray
    $result = sqlcmd -S "localhost,$Port" -U sa -P $Password `
        -i $scriptPath `
        -t 300 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Workload database created" -ForegroundColor Green

        # Execute the workload for 5 minutes
        Write-Host "  Executing workload (5 minutes)..." -ForegroundColor Gray
        $workloadCmd = @"
USE [WorkloadTest];
EXEC [dbo].[Execute_ScaledWorkload]
    @DurationMinutes = 5,
    @ReadPercentage = $ReadPct,
    @WritePercentage = $WritePct;
"@

        $workloadFile = Join-Path $ResultsDir "${ContainerName}_workload_exec.sql"
        $workloadCmd | Out-File -FilePath $workloadFile -Encoding UTF8

        $result = sqlcmd -S "localhost,$Port" -U sa -P $Password `
            -i $workloadFile `
            -t 600 2>&1

        Write-Host "  Workload execution complete" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  Failed to setup workload" -ForegroundColor Red
        return $false
    }
}

# =============================================
# Function: Install QSAutomation
# =============================================
function Install-QSAutomation {
    param($Port, $ContainerName)

    Write-Host "Installing QSAutomation on port $Port..." -ForegroundColor Cyan

    # Install Step 0 (schema)
    $step0 = Get-Content "G:\My Drive\backups\repos\querystore-autotuning\Step 0 - Setup.sql" -Raw
    if ($step0) {
        $setupFile = Join-Path $ResultsDir "${ContainerName}_qs_step0.sql"

        # Modify to use WorkloadTest database
        $step0Modified = "USE [WorkloadTest];`n" + $step0
        $step0Modified | Out-File -FilePath $setupFile -Encoding UTF8

        $result = sqlcmd -S "localhost,$Port" -U sa -P $Password -i $setupFile 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Step 0 installed successfully" -ForegroundColor Green
        } else {
            Write-Host "  Step 0 installation failed" -ForegroundColor Red
            return $false
        }
    }

    # Install Step 1 (High Variation Check)
    $step1 = Get-Content "G:\My Drive\backups\repos\querystore-autotuning\Step 1 - High Variation Check.sql" -Raw
    if ($step1) {
        $step1File = Join-Path $ResultsDir "${ContainerName}_qs_step1.sql"

        # Modify to use WorkloadTest database
        $step1Modified = "USE [WorkloadTest];`n" + $step1
        $step1Modified | Out-File -FilePath $step1File -Encoding UTF8

        $result = sqlcmd -S "localhost,$Port" -U sa -P $Password -i $step1File 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Step 1 installed successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  Step 1 installation failed" -ForegroundColor Red
            return $false
        }
    }

    return $false
}

# =============================================
# Function: Run QSAutomation Test
# =============================================
function Test-QSAutomation {
    param($Port, $ContainerName)

    Write-Host "Testing QSAutomation on port $Port..." -ForegroundColor Cyan

    $testScript = @"
USE [WorkloadTest];

-- Run High Variation Check
EXEC QSAutomation.QueryStore_HighVariationCheck;

-- Query results
SELECT 'QUERIES_TRACKED' AS [ResultType], COUNT(*) AS [Count] FROM QSAutomation.Query;
SELECT 'ACTIVITY_LOG' AS [ResultType], COUNT(*) AS [Count] FROM QSAutomation.ActivityLog;

-- Show any pinned plans
SELECT
    q.query_id,
    q.Status,
    q.pinned_plan_id,
    q.t_Statistic,
    q.DateCreated
FROM QSAutomation.Query q
WHERE q.pinned_plan_id IS NOT NULL;

-- Show Query Store stats
SELECT 'QUERY_STORE_QUERIES' AS [ResultType], COUNT(*) AS [Count] FROM sys.query_store_query;
SELECT 'QUERY_STORE_PLANS' AS [ResultType], COUNT(*) AS [Count] FROM sys.query_store_plan;
"@

    $testFile = Join-Path $ResultsDir "${ContainerName}_qs_test.sql"
    $testScript | Out-File -FilePath $testFile -Encoding UTF8

    $outputFile = Join-Path $ResultsDir "${ContainerName}_qs_results.txt"

    $result = sqlcmd -S "localhost,$Port" -U sa -P $Password `
        -i $testFile `
        -o $outputFile `
        -y 0

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  QSAutomation test results saved to: $outputFile" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  QSAutomation test failed" -ForegroundColor Red
        return $false
    }
}

# =============================================
# Function: Capture Final Profile
# =============================================
function Get-FinalProfile {
    param($Port, $ContainerName)

    Write-Host "Capturing final profile on port $Port..." -ForegroundColor Cyan

    $outputFile = Join-Path $ResultsDir "${ContainerName}_profile_final.txt"

    $result = sqlcmd -S "localhost,$Port" -U sa -P $Password `
        -i "G:\My Drive\backups\repos\querystore-autotuning\workload_profile_helper.sql" `
        -o $outputFile `
        -y 0

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Final profile saved to: $outputFile" -ForegroundColor Green
        return $outputFile
    } else {
        Write-Host "  Failed to capture final profile" -ForegroundColor Red
        return $null
    }
}

# =============================================
# MAIN EXECUTION
# =============================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Multi-Container Test Workflow" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$testResults = @()

foreach ($container in $Containers) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Processing: $($container.Name)" -ForegroundColor Magenta
    Write-Host "Description: $($container.Description)" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""

    $containerResult = @{
        Name = $container.Name
        Port = $container.Port
        CPUs = $container.CPUs
        Memory = $container.Memory
        Steps = @{}
    }

    # Step 1: Cleanup
    Write-Host "[1/8] Cleanup existing container" -ForegroundColor Yellow
    Remove-TestContainer -ContainerName $container.Name
    $containerResult.Steps["Cleanup"] = "Success"

    # Step 2: Create
    Write-Host "[2/8] Create new container" -ForegroundColor Yellow
    $created = New-TestContainer -Name $container.Name -Port $container.Port -CPUs $container.CPUs -Memory $container.Memory
    $containerResult.Steps["Create"] = if ($created) { "Success" } else { "Failed" }

    if (-not $created) {
        Write-Host "Skipping remaining steps for $($container.Name)" -ForegroundColor Red
        $testResults += $containerResult
        continue
    }

    # Step 3: Wait for SQL Server
    Write-Host "[3/8] Wait for SQL Server to be ready" -ForegroundColor Yellow
    $ready = Wait-SqlServer -Port $container.Port
    $containerResult.Steps["Wait"] = if ($ready) { "Success" } else { "Failed" }

    if (-not $ready) {
        Write-Host "Skipping remaining steps for $($container.Name)" -ForegroundColor Red
        $testResults += $containerResult
        continue
    }

    # Step 4: Capture baseline profile
    Write-Host "[4/8] Capture baseline diagnostic profile" -ForegroundColor Yellow
    $profileFile = Invoke-DiagnosticProfile -Port $container.Port -ContainerName $container.Name
    $containerResult.Steps["BaselineProfile"] = if ($profileFile) { "Success: $profileFile" } else { "Failed" }

    # Step 5: Generate workload
    Write-Host "[5/8] Generate scaled test workload" -ForegroundColor Yellow
    $workloadGenerated = New-TestWorkload -Port $container.Port -ContainerName $container.Name
    $containerResult.Steps["GenerateWorkload"] = if ($workloadGenerated) { "Success" } else { "Failed" }

    if (-not $workloadGenerated) {
        Write-Host "Skipping remaining steps for $($container.Name)" -ForegroundColor Red
        $testResults += $containerResult
        continue
    }

    # Step 6: Install QSAutomation
    Write-Host "[6/8] Install QSAutomation" -ForegroundColor Yellow
    $qsInstalled = Install-QSAutomation -Port $container.Port -ContainerName $container.Name
    $containerResult.Steps["InstallQS"] = if ($qsInstalled) { "Success" } else { "Failed" }

    # Step 7: Test QSAutomation
    Write-Host "[7/8] Run QSAutomation tests" -ForegroundColor Yellow
    $qsTested = Test-QSAutomation -Port $container.Port -ContainerName $container.Name
    $containerResult.Steps["TestQS"] = if ($qsTested) { "Success" } else { "Failed" }

    # Step 8: Capture final profile
    Write-Host "[8/8] Capture final diagnostic profile" -ForegroundColor Yellow
    $finalProfile = Get-FinalProfile -Port $container.Port -ContainerName $container.Name
    $containerResult.Steps["FinalProfile"] = if ($finalProfile) { "Success: $finalProfile" } else { "Failed" }

    $testResults += $containerResult

    Write-Host ""
    Write-Host "Completed: $($container.Name)" -ForegroundColor Green
    Write-Host ""
}

# =============================================
# SUMMARY REPORT
# =============================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($result in $testResults) {
    Write-Host "Container: $($result.Name) (Port: $($result.Port), CPUs: $($result.CPUs), Memory: $($result.Memory))" -ForegroundColor Yellow

    foreach ($step in $result.Steps.GetEnumerator()) {
        $status = if ($step.Value -like "Success*") { "[OK]" } else { "[FAIL]" }
        $color = if ($step.Value -like "Success*") { "Green" } else { "Red" }
        Write-Host "  $status $($step.Key): $($step.Value)" -ForegroundColor $color
    }
    Write-Host ""
}

Write-Host "All results saved to: $ResultsDir" -ForegroundColor Cyan
Write-Host ""

# =============================================
# GENERATE SUMMARY DOCUMENT
# =============================================

$summaryPath = Join-Path $ResultsDir "test_summary.md"

$summary = @"
# Multi-Container Testing Summary

**Test Date:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Results Directory:** $ResultsDir

## Container Configurations

$(foreach ($container in $Containers) {
@"

### $($container.Name)
- **Port:** $($container.Port)
- **CPUs:** $($container.CPUs)
- **Memory:** $($container.Memory)
- **Description:** $($container.Description)
- **Expected Workload:** $($container.WorkloadType)

"@
})

## Test Results

$(foreach ($result in $testResults) {
@"

### $($result.Name)

$(foreach ($step in $result.Steps.GetEnumerator() | Sort-Object Name) {
"- **$($step.Key):** $($step.Value)"
})

"@
})

## Files Generated

Check the results directory for:
- *_profile.txt - Baseline diagnostic profiles
- *_profile_final.txt - Final profiles after workload
- *_qs_results.txt - QSAutomation test results
- *_workload_*.sql - Generated workload scripts

## Next Steps

1. Review diagnostic profiles to see captured characteristics
2. Compare baseline vs final profiles to see workload impact
3. Analyze QSAutomation results across different container sizes
4. Use profiles to refine test workload generation

"@

$summary | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host "Summary document created: $summaryPath" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
