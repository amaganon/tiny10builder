# Windows 10 Optimizer Script - Live System
# Version: 02-04-25

# Check PowerShell execution policy
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "The current PowerShell execution policy is set to Restricted, which prevents scripts from running. Would you like to change it to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "The script cannot run without changing the execution policy. Exiting..."
        exit
    }
}

# Verify and run as administrator
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "This script requires administrator privileges. Restarting with elevation..."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# Start logging
$dateTime = Get-Date -Format "yyyy-MM-dd-HH-mm"
Start-Transcript -Path "$env:USERPROFILE\Desktop\windows10_optimization_$dateTime.log"

# Configure window title
$Host.UI.RawUI.WindowTitle = "Windows 10 Optimizer"
Clear-Host
Write-Host "Welcome to Windows 10 Optimizer! Version: 02-04-25"
Write-Host "WARNING: This script will modify system settings. It's recommended to create a restore point before continuing."
Write-Host "Would you like to create a restore point now? (yes/no)"
$createRestore = Read-Host

if ($createRestore -eq 'yes') {
    Enable-ComputerRestore -Drive "$env:SystemDrive"
    Checkpoint-Computer -Description "Before Windows 10 Optimization" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "Restore point created successfully."
}

Write-Host "`nStarting optimization process...`n"

# Remove unwanted preinstalled apps
Write-Host "Removing preinstalled applications..."
$appsToRemove = @(
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "microsoft.windowscommunicationsapps"
)

foreach ($app in $appsToRemove) {
    Write-Host "Removing $app"
    Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online
}

# Disable non-essential services
Write-Host "`nDisabling non-essential services..."
$servicesToDisable = @(
    "DiagTrack",                # Windows Telemetry
    "dmwappushservice",         # WAP Push Message Routing Service
    "WSearch"                   # Windows Search
)

foreach ($service in $servicesToDisable) {
    Write-Host "Disabling service: $service"
    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
    Set-Service -Name $service -StartupType Disabled
}

# Disable telemetry and data collection
Write-Host "`nConfiguring privacy policies..."
$registryPaths = @{
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{
        "AllowTelemetry" = 0
    }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{
        "AllowTelemetry" = 0
    }
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" = @{
        "ContentDeliveryAllowed" = 0
        "OemPreInstalledAppsEnabled" = 0
        "PreInstalledAppsEnabled" = 0
        "SilentInstalledAppsEnabled" = 0
        "SystemPaneSuggestionsEnabled" = 0
    }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" = @{
        "DisableWindowsConsumerFeatures" = 1
    }
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" = @{
        "TailoredExperiencesWithDiagnosticDataEnabled" = 0
    }
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" = @{
        "Enabled" = 0
    }
}

foreach ($path in $registryPaths.Keys) {
    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    
    $registryPaths[$path].Keys | ForEach-Object {
        Set-ItemProperty -Path $path -Name $_ -Value $registryPaths[$path][$_]
    }
}

# Uninstall Edge (optional)
Write-Host "`nWould you like to uninstall Microsoft Edge? (yes/no)"
$uninstallEdge = Read-Host

if ($uninstallEdge -eq 'yes') {
    Write-Host "Uninstalling Microsoft Edge..."
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    if (Test-Path $edgePath) {
        $installerPath = Get-ChildItem -Path $edgePath -Filter "setup.exe" -Recurse | Select-Object -First 1
        if ($installerPath) {
            Start-Process -FilePath $installerPath.FullName -ArgumentList "--uninstall --system-level --force-uninstall" -Wait
        }
    }
}

# Uninstall OneDrive (optional)
Write-Host "`nWould you like to uninstall OneDrive? (yes/no)"
$uninstallOneDrive = Read-Host

if ($uninstallOneDrive -eq 'yes') {
    Write-Host "Uninstalling OneDrive..."
    Stop-Process -Name OneDrive -ErrorAction SilentlyContinue
    Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" "/uninstall" -Wait
    Remove-Item "$env:UserProfile\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:LocalAppData\Microsoft\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:ProgramData\Microsoft OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemDrive\OneDriveTemp" -Force -Recurse -ErrorAction SilentlyContinue
}

# Clean temporary files and cache
Write-Host "`nCleaning temporary files..."
Remove-Item "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Run system cleanup
Write-Host "`nRunning system cleanup..."
cleanmgr /sagerun:1

Write-Host "`nOptimization completed!"
Write-Host "A log file has been created on your desktop with operation details."
Write-Host "It's recommended to restart the system to apply all changes."
Write-Host "`nWould you like to restart the system now? (yes/no)"
$restart = Read-Host

if ($restart -eq 'yes') {
    Stop-Transcript
    Restart-Computer -Force
} else {
    Stop-Transcript
    Write-Host "Please restart the system manually at your convenience."
}