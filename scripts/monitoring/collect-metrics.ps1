# PowerShell script to collect performance metrics from an EC2 instance

param (
    [Parameter(Mandatory=$true)]
    [string]$InstanceId,
    
    [string]$Region = "us-east-1",
    
    [string]$OutputPath = "../../artifacts/metrics",
    
    [string]$TestId = (Get-Date -Format "yyyyMMdd-HHmmss"),
    
    [int]$DurationMinutes = 10,
    
    [int]$SamplingIntervalSeconds = 60
)

# Check if AWS PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name AWSPowerShell)) {
    Write-Host "AWS PowerShell module not found. Installing..."
    Install-Module -Name AWSPowerShell -Force
}

# Import AWS PowerShell module
Import-Module AWSPowerShell

# Ensure output directory exists
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $OutputPath"
}

# Set the time range for metrics collection
$endTime = Get-Date
$startTime = $endTime.AddMinutes(-$DurationMinutes)

Write-Host "Collecting metrics for instance $InstanceId from $startTime to $endTime..."

# Function to get CloudWatch metrics
function Get-CloudWatchMetric {
    param (
        [string]$Namespace,
        [string]$MetricName,
        [hashtable]$Dimensions,
        [string]$Statistic = "Average",
        [int]$Period = 60
    )
    
    $metric = Get-CWMetricStatistic -Namespace $Namespace -MetricName $MetricName -Dimension $Dimensions `
                                   -StartTime $startTime -EndTime $endTime -Period $Period -Statistic $Statistic `
                                   -Region $Region
    
    return $metric
}

# Collect CPU utilization metrics
Write-Host "Collecting CPU utilization metrics..."
$cpuMetrics = Get-CloudWatchMetric -Namespace "AWS/EC2" -MetricName "CPUUtilization" `
                                  -Dimensions @{Name="InstanceId";Value=$InstanceId} `
                                  -Period $SamplingIntervalSeconds

# Collect memory utilization metrics (requires CloudWatch agent)
Write-Host "Collecting memory utilization metrics..."
$memoryMetrics = Get-CloudWatchMetric -Namespace "CWAgent" -MetricName "Memory % Committed Bytes In Use" `
                                     -Dimensions @{Name="InstanceId";Value=$InstanceId} `
                                     -Period $SamplingIntervalSeconds

# Collect network metrics
Write-Host "Collecting network metrics..."
$networkInMetrics = Get-CloudWatchMetric -Namespace "AWS/EC2" -MetricName "NetworkIn" `
                                        -Dimensions @{Name="InstanceId";Value=$InstanceId} `
                                        -Period $SamplingIntervalSeconds
$networkOutMetrics = Get-CloudWatchMetric -Namespace "AWS/EC2" -MetricName "NetworkOut" `
                                         -Dimensions @{Name="InstanceId";Value=$InstanceId} `
                                         -Period $SamplingIntervalSeconds

# Format CPU metrics for output
$cpuData = $cpuMetrics.Datapoints | Select-Object @{Name="Timestamp";Expression={$_.Timestamp}}, 
                                                 @{Name="CPUUtilization";Expression={$_.Average}} |
                                    Sort-Object Timestamp

# Format memory metrics for output
$memoryData = $memoryMetrics.Datapoints | Select-Object @{Name="Timestamp";Expression={$_.Timestamp}}, 
                                                       @{Name="MemoryUtilization";Expression={$_.Average}} |
                                          Sort-Object Timestamp

# Format network metrics for output
$networkData = $networkInMetrics.Datapoints | ForEach-Object {
    $timestamp = $_.Timestamp
    $networkIn = $_.Average
    $networkOut = ($networkOutMetrics.Datapoints | Where-Object { $_.Timestamp -eq $timestamp }).Average
    
    [PSCustomObject]@{
        Timestamp = $timestamp
        NetworkIn = $networkIn
        NetworkOut = $networkOut
    }
} | Sort-Object Timestamp

# Save metrics to CSV files
$cpuOutputPath = Join-Path -Path $OutputPath -ChildPath "cpu_metrics_$TestId.csv"
$memoryOutputPath = Join-Path -Path $OutputPath -ChildPath "memory_metrics_$TestId.csv"
$networkOutputPath = Join-Path -Path $OutputPath -ChildPath "network_metrics_$TestId.csv"

$cpuData | Export-Csv -Path $cpuOutputPath -NoTypeInformation
$memoryData | Export-Csv -Path $memoryOutputPath -NoTypeInformation
$networkData | Export-Csv -Path $networkOutputPath -NoTypeInformation

Write-Host "Metrics saved to:"
Write-Host "  CPU: $cpuOutputPath"
Write-Host "  Memory: $memoryOutputPath"
Write-Host "  Network: $networkOutputPath"

# Generate summary statistics
$cpuAvg = ($cpuData | Measure-Object -Property CPUUtilization -Average).Average
$cpuMax = ($cpuData | Measure-Object -Property CPUUtilization -Maximum).Maximum
$memoryAvg = ($memoryData | Measure-Object -Property MemoryUtilization -Average).Average
$memoryMax = ($memoryData | Measure-Object -Property MemoryUtilization -Maximum).Maximum
$networkInAvg = ($networkData | Measure-Object -Property NetworkIn -Average).Average
$networkOutAvg = ($networkData | Measure-Object -Property NetworkOut -Average).Average

# Create summary report
$summaryReport = @"
# Performance Metrics Summary for Instance $InstanceId
Test ID: $TestId
Time Range: $startTime to $endTime
Duration: $DurationMinutes minutes
Sampling Interval: $SamplingIntervalSeconds seconds

## CPU Utilization
- Average: $($cpuAvg.ToString("0.00"))%
- Maximum: $($cpuMax.ToString("0.00"))%

## Memory Utilization
- Average: $($memoryAvg.ToString("0.00"))%
- Maximum: $($memoryMax.ToString("0.00"))%

## Network Traffic
- Average Network In: $($networkInAvg.ToString("0.00")) bytes/sec
- Average Network Out: $($networkOutAvg.ToString("0.00")) bytes/sec
"@

$summaryPath = Join-Path -Path $OutputPath -ChildPath "summary_$TestId.md"
$summaryReport | Out-File -FilePath $summaryPath -Encoding utf8

Write-Host "Summary report saved to: $summaryPath"

# Return the paths to the output files
return @{
    CPUMetricsPath = $cpuOutputPath
    MemoryMetricsPath = $memoryOutputPath
    NetworkMetricsPath = $networkOutputPath
    SummaryPath = $summaryPath
    TestId = $TestId
}
