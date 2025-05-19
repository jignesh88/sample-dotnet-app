# PowerShell script to build and package the .NET web application

param (
    [string]$ProjectPath = "../../SampleWebApp",
    [string]$Configuration = "Release",
    [string]$OutputPath = "../../artifacts",
    [string]$PackageName = "SampleWebApp.zip"
)

# Ensure output directory exists
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $OutputPath"
}

# Clean previous build artifacts
Write-Host "Cleaning previous build artifacts..."
dotnet clean $ProjectPath --configuration $Configuration

# Restore dependencies
Write-Host "Restoring dependencies..."
dotnet restore $ProjectPath

# Build the project
Write-Host "Building project with configuration: $Configuration..."
dotnet build $ProjectPath --configuration $Configuration --no-restore

# Publish the application
Write-Host "Publishing application..."
dotnet publish $ProjectPath --configuration $Configuration --no-build --output "$OutputPath/publish"

# Create deployment package
Write-Host "Creating deployment package: $PackageName..."
$packagePath = Join-Path -Path $OutputPath -ChildPath $PackageName
if (Test-Path $packagePath) {
    Remove-Item $packagePath -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory("$OutputPath/publish", $packagePath)

Write-Host "Deployment package created successfully at: $packagePath"
