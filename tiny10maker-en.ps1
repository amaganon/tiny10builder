# Enable debugging if needed
#Set-PSDebug -Trace 1

param (
    [ValidatePattern('^[c-zC-Z]$')]
    [string]$WorkDrive
)

if (-not $WorkDrive) {
    $WorkDrive = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $WorkDrive = $WorkDrive + ":"
}

Write-Output "Working drive set to $WorkDrive"

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
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

if (! $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "Restarting Tiny10 image creator as administrator in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

# Start logging and prepare window
Start-Transcript -Path "$WorkDrive\tiny10.log" 

$Host.UI.RawUI.WindowTitle = "Tiny10 Image Creator"
Clear-Host
Write-Host "Welcome to the Tiny10 Image Creator! Version: 02-04-25"

$systemArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$WorkDrive\tiny10\sources" | Out-Null

do {
    $DriveLetter = Read-Host "Please enter the drive letter where the Windows 10 image is mounted"
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "Drive letter set to $DriveLetter"
    } else {
        Write-Output "Invalid drive letter. Please enter a letter between C and Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

# Check installation files
if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Host "Found install.esd, converting to install.wim..."
        Get-WindowsImage -ImagePath $DriveLetter\sources\install.esd
        $index = Read-Host "Please enter the image index"
        Write-Host ' '
        Write-Host 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath $WorkDrive\tiny10\sources\install.wim -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Host "Windows installation files not found in the specified drive."
        Write-Host "Please enter the correct drive letter."
        exit
    }
}

Write-Host "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$WorkDrive\tiny10" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$WorkDrive\tiny10\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$WorkDrive\tiny10\sources\install.esd" > $null 2>&1
Write-Host "Copy completed!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Getting image information:"
Get-WindowsImage -ImagePath $WorkDrive\tiny10\sources\install.wim
$index = Read-Host "Please enter the image index"

Write-Host "Mounting Windows image. This may take a while..."
$wimPath = "$WorkDrive\tiny10\sources\install.wim"
& takeown "/F" $wimPath 
& icacls $wimPath "/grant" "$($adminGroup.Value):(F)"

try {
    Set-ItemProperty -Path $wimPath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # Suppress error if it occurs
}

New-Item -ItemType Directory -Force -Path "$WorkDrive\tempdirectory" > $null
Mount-WindowsImage -ImagePath $WorkDrive\tiny10\sources\install.wim -Index $index -Path $WorkDrive\tempdirectory

# Get system language information
$langInfo = & dism /Get-Intl "/Image:$($WorkDrive)\tempdirectory"
$langLine = $langInfo -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($langLine) {
    $langCode = $Matches[1]
    Write-Host "System language code: $langCode"
} else {
    Write-Host "Language code not found."
}

# Get architecture information
$imageInfo = & dism '/Get-WimInfo' "/wimFile:$($WorkDrive)\tiny10\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        if ($architecture -eq 'x64') {
            $architecture = 'amd64'
        }
        Write-Host "Architecture: $architecture"
        break
    }
}

if (-not $architecture) {
    Write-Host "Architecture information not found."
}

Write-Host "Mount completed! Proceeding to remove applications..."

# List of applications to remove (keeping Xbox)
$packages = & dism "/image:$($WorkDrive)\tempdirectory" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'Package Name : (.*)') {
            $matches[1]
        }
    }

$packagePrefixes = @(
    'Microsoft.BingNews_',
    'Microsoft.BingWeather_',
    'Microsoft.GetHelp_',
    'Microsoft.Getstarted_',
    'Microsoft.MicrosoftOfficeHub_',
    'Microsoft.MicrosoftSolitaireCollection_',
    'Microsoft.People_',
    'Microsoft.WindowsFeedbackHub_',
    'Microsoft.WindowsMaps_',
    'Microsoft.WindowsSoundRecorder_',
    'Microsoft.YourPhone_',
    'Microsoft.ZuneMusic_',
    'Microsoft.ZuneVideo_',
    'microsoft.windowscommunicationsapps_'
)

$packagesToRemove = $packages | Where-Object {
    $packageName = $_
    $packagePrefixes -contains ($packagePrefixes | Where-Object { $packageName -like "$_*" })
}

foreach ($package in $packagesToRemove) {
    & dism "/image:$($WorkDrive)\tempdirectory" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}

Write-Host "Removing Edge..."
Remove-Item -Path "$WorkDrive\tempdirectory\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
Remove-Item -Path "$WorkDrive\tempdirectory\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
Remove-Item -Path "$WorkDrive\tempdirectory\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null

Write-Host "Removing OneDrive..."
& takeown "/f" "$WorkDrive\tempdirectory\Windows\System32\OneDriveSetup.exe" | Out-Null
& icacls "$WorkDrive\tempdirectory\Windows\System32\OneDriveSetup.exe" "/grant" "$($adminGroup.Value):(F)" "/T" "/C" | Out-Null
Remove-Item -Path "$WorkDrive\tempdirectory\Windows\System32\OneDriveSetup.exe" -Force | Out-Null

Write-Host "Removal completed!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Loading registry..."
reg load HKLM\zCOMPONENTS "$WorkDrive\tempdirectory\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$WorkDrive\tempdirectory\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$WorkDrive\tempdirectory\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$WorkDrive\tempdirectory\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$WorkDrive\tempdirectory\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Disabling sponsored apps..."
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f | Out-Null

Write-Host "Disabling telemetry..."
& reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f | Out-Null

# Services to disable (keeping Xbox services)
$servicesToDisable = @(
    "DiagTrack",                # Windows Telemetry
    "dmwappushservice",         # WAP Push Message Routing Service
    "WSearch"                   # Windows Search
)

foreach ($service in $servicesToDisable) {
    & reg add "HKLM\zSYSTEM\ControlSet001\Services\$service" /v "Start" /t REG_DWORD /d 4 /f | Out-Null
}

Write-Host "Unloading registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Cleaning image..."
Repair-WindowsImage -Path $WorkDrive\tempdirectory -StartComponentCleanup -ResetBase
Write-Host "Cleanup completed."

Write-Host "Dismounting image..."
Dismount-WindowsImage -Path $WorkDrive\tempdirectory -Save

Write-Host "Exporting image..."
Export-WindowsImage -SourceImagePath $WorkDrive\tiny10\sources\install.wim -SourceIndex $index -DestinationImagePath $WorkDrive\tiny10\sources\install2.wim -CompressionType Fast
Remove-Item -Path "$WorkDrive\tiny10\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$WorkDrive\tiny10\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Host "Processing boot.wim image..."

# CREATE ISO IMAGE

Write-Host "Verifying oscdimg.exe presence..."
$oscdimgPath = Join-Path $PSScriptRoot "oscdimg.exe"

if (-not (Test-Path $oscdimgPath)) {
    Write-Host "ERROR: oscdimg.exe not found in the current directory."
    Write-Host "Please ensure oscdimg.exe is located in the same directory as this script."
    exit
}

Write-Host "Creating ISO file..."
$dateTime = Get-Date -Format "yyyyMMdd-HHmm"
$isoName = "tiny10_$dateTime.iso"
$isoPath = Join-Path $WorkDrive $isoName

# Create ISO using oscdimg
& $oscdimgPath -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$WorkDrive\tiny10\boot\etfsboot.com"#pEF,e,b"$WorkDrive\tiny10\efi\microsoft\boot\efisys.bin" "$WorkDrive\tiny10" "$isoPath"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nProcess completed successfully!"
    Write-Host "ISO file has been created at: $isoPath"
} else {
    Write-Host "`nError creating ISO file. Error code: $LASTEXITCODE"
}

# Clean up temporary files
Write-Host "`nCleaning up temporary files..."
Remove-Item -Path "$WorkDrive\tiny10" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$WorkDrive\tempdirectory" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Process finished."

Stop-Transcript

Clear-Host