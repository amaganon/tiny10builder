# Enable debugging if needed
#Set-PSDebug -Trace 1

param (
    [ValidatePattern('^[c-zC-Z]$')]
    [string]$ScratchDisk
)

if (-not $ScratchDisk) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $ScratchDisk + ":"
}

Write-Output "Scratch disk set to $ScratchDisk"

# Check if PowerShell execution is restricted
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "The script cannot be run without changing the execution policy. Exiting..."
        exit
    }
}

# Check and run the script as admin if required
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "Restarting Tiny10 image creator as admin in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# Start the transcript and prepare the window
Start-Transcript -Path "$ScratchDisk\tiny10.log"

$Host.UI.RawUI.WindowTitle = "Tiny10 image creator"
Clear-Host
Write-Host "Welcome to the tiny10 image creator! Release: 05-02-24"

# Ask about Edge and OneDrive
$removeEdge = Read-Host "Would you like to remove Microsoft Edge? (yes/no)"
$removeOneDrive = Read-Host "Would you like to remove OneDrive? (yes/no)"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny10\sources" | Out-Null

do {
    $DriveLetter = Read-Host "Please enter the drive letter for the Windows 10 image"
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "Drive letter set to $DriveLetter"
    } else {
        Write-Output "Invalid drive letter. Please enter a letter between C and Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Host "Found install.esd, converting to install.wim..."
        Get-WindowsImage -ImagePath "$DriveLetter\sources\install.esd"
        $index = Read-Host "Please enter the image index"
        Write-Host " "
        Write-Host "Converting install.esd to install.wim. This may take a while..."
        Export-WindowsImage -SourceImagePath "$DriveLetter\sources\install.esd" -SourceIndex $index -DestinationImagePath "$ScratchDisk\tiny10\sources\install.wim" -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Host "Can't find Windows OS Installation files in the specified Drive Letter."
        Write-Host "Please enter the correct DVD Drive Letter."
        exit
    }
}

Write-Host "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny10" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\tiny10\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$ScratchDisk\tiny10\sources\install.esd" > $null 2>&1
Write-Host "Copy complete!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Getting image information:"
Get-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\install.wim"
$index = Read-Host "Please enter the image index"

Write-Host "Mounting Windows image. This may take a while."
$wimFilePath = "$ScratchDisk\tiny10\sources\install.wim"
& takeown "/F" $wimFilePath 
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"

try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # This block will catch the error and suppress it.
}

New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\install.wim" -Index $index -Path "$ScratchDisk\scratchdir"

# Get image information
$imageInfo = & dism /English /Get-WimInfo "/wimFile:$($ScratchDisk)\tiny10\sources\install.wim" "/index:$index"
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

Write-Host "Mounting complete! Performing removal of applications..."

# Windows 10 specific apps to remove (keeping Xbox)
$packages = & dism "/image:$($ScratchDisk)\scratchdir" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'PackageName : (.*)') {
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
    & dism "/image:$($ScratchDisk)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}

if ($removeEdge -eq 'yes') {
    Write-Host "Removing Edge:"
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null
}

if ($removeOneDrive -eq 'yes') {
    Write-Host "Removing OneDrive:"
    & takeown "/f" "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" | Out-Null
    & icacls "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" "/grant" "$($adminGroup.Value):(F)" "/T" "/C" | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force | Out-Null
}

Write-Host "Removal complete!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Loading registry..."
reg load HKLM\zCOMPONENTS "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$ScratchDisk\scratchdir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDisk\scratchdir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Disabling Sponsored Apps:"
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f | Out-Null

Write-Host "Disabling Telemetry:"
& reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f | Out-Null

Write-Host "Unloading Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Cleaning up image..."
Repair-WindowsImage -Path "$ScratchDisk\scratchdir" -StartComponentCleanup -ResetBase
Write-Host "Cleanup complete."

Write-Host "Unmounting image..."
Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Save

Write-Host "Exporting image..."
Export-WindowsImage -SourceImagePath "$ScratchDisk\tiny10\sources\install.wim" -SourceIndex $index -DestinationImagePath "$ScratchDisk\tiny10\sources\install2.wim" -CompressionType Fast
Remove-Item -Path "$ScratchDisk\tiny10\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny10\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Host "Processing boot.wim..."
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\boot.wim" -Index 2 -Path "$ScratchDisk\scratchdir"

Write-Host "Loading registry..."
reg load HKLM\zCOMPONENTS "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$ScratchDisk\scratchdir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDisk\scratchdir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Unloading Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Unmounting image..."
Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Save

Write-Host "The tiny10 image is now completed. Proceeding with the making of the ISO..."
Write-Host "Copying unattended file..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\tiny10\autounattend.xml" -Force | Out-Null

Write-Host "Creating ISO image..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Host "Will be using oscdimg.exe from system ADK."
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Host "ADK folder not found. Will be using bundled oscdimg.exe."
    
    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Error "ERROR: oscdimg.exe not found in current directory ($PSScriptRoot)"
        Write-Host "Please ensure oscdimg.exe is in the same directory as this script."
        exit 1
    } else {
        Write-Host "Using local oscdimg.exe"
    }
    
    $OSCDIMG = $localOSCDIMGPath
}

# Create timestamp for ISO filename
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$isoName = "tiny10_$timestamp.iso"
$isoPath = Join-Path $PSScriptRoot $isoName

Write-Host "Generating ISO file at: $isoPath"
Write-Host "This process may take several minutes..."

# Create the ISO using oscdimg
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny10\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny10\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny10" "$isoPath"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nISO creation completed successfully!"
    Write-Host "The ISO file has been created at: $isoPath"
} else {
    Write-Error "Error creating ISO file. Error code: $LASTEXITCODE"
    exit 1
}

# Clean up
Write-Host "`nPerforming cleanup..."
Remove-Item -Path "$ScratchDisk\tiny10" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null

Write-Host "`nProcess completed successfully."
Write-Host "The ISO file is located at: $isoPath"
Write-Host "The process log can be found at: $PSScriptRoot\tiny10.log"

Stop-Transcript