# PowerShell script to deploy the .NET web application to an EC2 instance with IIS

param (
    [Parameter(Mandatory=$true)]
    [string]$InstanceId,
    
    [Parameter(Mandatory=$true)]
    [string]$S3BucketName,
    
    [string]$PackagePath = "../../artifacts/SampleWebApp.zip",
    
    [string]$S3Key = "deployments/SampleWebApp.zip",
    
    [string]$WebsiteName = "WebApp",
    
    [string]$ApplicationPoolName = "WebAppPool",
    
    [string]$WebsitePath = "C:\WebApp",
    
    [string]$Region = "us-east-1"
)

# Check if AWS PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name AWSPowerShell)) {
    Write-Host "AWS PowerShell module not found. Installing..."
    Install-Module -Name AWSPowerShell -Force
}

# Import AWS PowerShell module
Import-Module AWSPowerShell

# Upload package to S3
Write-Host "Uploading deployment package to S3..."
Write-S3Object -BucketName $S3BucketName -File $PackagePath -Key $S3Key -Region $Region

# Create SSM command document to deploy the application
$deploymentScript = @"
# Download deployment package from S3
aws s3 cp s3://$S3BucketName/$S3Key C:\Temp\SampleWebApp.zip --region $Region

# Create temp directory for extraction
if (-not (Test-Path -Path C:\Temp)) {
    New-Item -Path C:\Temp -ItemType Directory -Force
}

# Stop the website if it exists
Import-Module WebAdministration
if (Get-Website -Name '$WebsiteName') {
    Stop-Website -Name '$WebsiteName'
    Write-Host "Stopped website: $WebsiteName"
}

# Extract the deployment package
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -Path '$WebsitePath') {
    Remove-Item -Path '$WebsitePath\*' -Recurse -Force
} else {
    New-Item -Path '$WebsitePath' -ItemType Directory -Force
}
[System.IO.Compression.ZipFile]::ExtractToDirectory('C:\Temp\SampleWebApp.zip', '$WebsitePath')

# Ensure application pool exists
if (-not (Get-ChildItem IIS:\AppPools | Where-Object { `$_.Name -eq '$ApplicationPoolName' })) {
    New-WebAppPool -Name '$ApplicationPoolName'
    Set-ItemProperty IIS:\AppPools\$ApplicationPoolName -Name managedRuntimeVersion -Value 'v4.0'
    Set-ItemProperty IIS:\AppPools\$ApplicationPoolName -Name managedPipelineMode -Value 'Integrated'
    Write-Host "Created application pool: $ApplicationPoolName"
}

# Ensure website exists
if (-not (Get-Website -Name '$WebsiteName')) {
    New-Website -Name '$WebsiteName' -PhysicalPath '$WebsitePath' -ApplicationPool '$ApplicationPoolName' -Port 80 -Force
    Write-Host "Created website: $WebsiteName"
} else {
    Set-ItemProperty IIS:\Sites\$WebsiteName -Name physicalPath -Value '$WebsitePath'
    Set-ItemProperty IIS:\Sites\$WebsiteName -Name applicationPool -Value '$ApplicationPoolName'
    Write-Host "Updated website: $WebsiteName"
}

# Start the website
Start-Website -Name '$WebsiteName'
Write-Host "Started website: $WebsiteName"

# Clean up
Remove-Item C:\Temp\SampleWebApp.zip -Force
Write-Host "Deployment completed successfully"
"@

# Save the deployment script to a temporary file
$tempScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
$deploymentScript | Out-File -FilePath $tempScriptPath -Encoding utf8

# Execute the deployment script on the EC2 instance using SSM
Write-Host "Deploying application to EC2 instance $InstanceId..."
$commandId = Send-SSMCommand -InstanceId $InstanceId -DocumentName "AWS-RunPowerShellScript" -Parameter @{
    "commands" = @($deploymentScript)
} -Region $Region

# Wait for the command to complete
Write-Host "Waiting for deployment to complete..."
$status = ""
do {
    Start-Sleep -Seconds 5
    $result = Get-SSMCommandInvocation -CommandId $commandId -InstanceId $InstanceId -Details $true -Region $Region
    $status = $result.Status
    Write-Host "Deployment status: $status"
} while ($status -eq "InProgress" -or $status -eq "Pending")

# Display the command output
$output = $result.CommandPlugins[0].Output
Write-Host "Deployment output:"
Write-Host $output

# Clean up temporary file
Remove-Item $tempScriptPath -Force

# Check if deployment was successful
if ($status -eq "Success") {
    Write-Host "Deployment completed successfully!"
} else {
    Write-Host "Deployment failed with status: $status"
    exit 1
}
