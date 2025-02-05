# Habilitar depuracion si es necesario
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

Write-Output "Disco temporal establecido en $ScratchDisk"

# Verificar si la ejecucion de PowerShell esta restringida
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "Tu politica actual de ejecucion de PowerShell esta configurada como Restringida, lo que impide que se ejecuten scripts. Deseas cambiarla a RemoteSigned? (si/no)"
    $response = Read-Host
    if ($response -eq 'si') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "El script no puede ejecutarse sin cambiar la politica de ejecucion. Saliendo..."
        exit
    }
}

# Verificar y ejecutar el script como administrador si es necesario
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "Reiniciando el creador de imagen Tiny10 como administrador en una nueva ventana, puedes cerrar esta."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# Iniciar la transcripcion y preparar la ventana
Start-Transcript -Path "$ScratchDisk\tiny10.log"

$Host.UI.RawUI.WindowTitle = "Creador de imagen Tiny10"
Clear-Host
Write-Host "Bienvenido al creador de imagen Tiny10! Version: 05-02-24"

# Preguntar sobre Edge y OneDrive
$removeEdge = Read-Host "Deseas eliminar Microsoft Edge? (si/no)"
$removeOneDrive = Read-Host "Deseas eliminar OneDrive? (si/no)"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny10\sources" | Out-Null

do {
    $DriveLetter = Read-Host "Por favor ingresa la letra de la unidad para la imagen de Windows 10"
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "Letra de unidad establecida en $DriveLetter"
    } else {
        Write-Output "Letra de unidad invalida. Por favor ingresa una letra entre C y Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Host "Se encontro install.esd, convirtiendo a install.wim..."
        Get-WindowsImage -ImagePath "$DriveLetter\sources\install.esd"
        $index = Read-Host "Por favor ingresa el indice de la imagen"
        Write-Host " "
        Write-Host "Convirtiendo install.esd a install.wim. Esto puede tomar un tiempo..."
        Export-WindowsImage -SourceImagePath "$DriveLetter\sources\install.esd" -SourceIndex $index -DestinationImagePath "$ScratchDisk\tiny10\sources\install.wim" -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Host "No se pueden encontrar los archivos de instalacion del sistema operativo Windows en la letra de unidad especificada."
        Write-Host "Por favor ingresa la letra de unidad de DVD correcta."
        exit
    }
}

Write-Host "Copiando imagen de Windows..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny10" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\tiny10\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$ScratchDisk\tiny10\sources\install.esd" > $null 2>&1
Write-Host "Copia completada!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Obteniendo informacion de la imagen:"
Get-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\install.wim"
$index = Read-Host "Por favor ingresa el indice de la imagen"

Write-Host "Montando imagen de Windows. Esto puede tomar un tiempo."
$wimFilePath = "$ScratchDisk\tiny10\sources\install.wim"
& takeown "/F" $wimFilePath 
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"

try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # Este bloque capturara el error y lo suprimira
}

New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\install.wim" -Index $index -Path "$ScratchDisk\scratchdir"

# Obtener informacion de la imagen
$imageInfo = & dism /English /Get-WimInfo "/wimFile:$($ScratchDisk)\tiny10\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        if ($architecture -eq 'x64') {
            $architecture = 'amd64'
        }
        Write-Host "Arquitectura: $architecture"
        break
    }
}

if (-not $architecture) {
    Write-Host "Informacion de arquitectura no encontrada."
}

Write-Host "Montaje completado! Realizando eliminacion de aplicaciones..."

# Aplicaciones especificas de Windows 10 para eliminar (manteniendo Xbox)
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

if ($removeEdge -eq 'si') {
    Write-Host "Eliminando Edge:"
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null
}

if ($removeOneDrive -eq 'si') {
    Write-Host "Eliminando OneDrive:"
    & takeown "/f" "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" | Out-Null
    & icacls "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" "/grant" "$($adminGroup.Value):(F)" "/T" "/C" | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force | Out-Null
}

Write-Host "Eliminacion completada!"

Start-Sleep -Seconds 2

Clear-Host

Write-Host "Cargando registro..."
reg load HKLM\zCOMPONENTS "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$ScratchDisk\scratchdir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDisk\scratchdir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Deshabilitando aplicaciones patrocinadas:"
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f | Out-Null

Write-Host "Deshabilitando Telemetria:"
& reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f | Out-Null

Write-Host "Descargando registro..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Limpiando imagen..."
Repair-WindowsImage -Path "$ScratchDisk\scratchdir" -StartComponentCleanup -ResetBase
Write-Host "Limpieza completada."

Write-Host "Desmontando imagen..."
Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Save

Write-Host "Exportando imagen..."
Export-WindowsImage -SourceImagePath "$ScratchDisk\tiny10\sources\install.wim" -SourceIndex $index -DestinationImagePath "$ScratchDisk\tiny10\sources\install2.wim" -CompressionType Fast
Remove-Item -Path "$ScratchDisk\tiny10\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny10\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Host "Procesando boot.wim..."
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny10\sources\boot.wim" -Index 2 -Path "$ScratchDisk\scratchdir"

Write-Host "Cargando registro..."
reg load HKLM\zCOMPONENTS "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$ScratchDisk\scratchdir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDisk\scratchdir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Descargando registro..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Desmontando imagen..."

Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Save

Write-Host "La imagen tiny10 esta ahora completada. Procediendo con la creacion del ISO..."
Write-Host "Copiando archivo desatendido..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\tiny10\autounattend.xml" -Force | Out-Null

Write-Host "Creando imagen ISO..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Host "Se utilizara oscdimg.exe del ADK del sistema."
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Host "Carpeta ADK no encontrada. Se utilizara el oscdimg.exe incluido."
    
    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Error "ERROR: oscdimg.exe no encontrado en el directorio actual ($PSScriptRoot)"
        Write-Host "Por favor asegurate de que oscdimg.exe este en el mismo directorio que este script."
        exit 1
    } else {
        Write-Host "Usando oscdimg.exe local"
    }
    
    $OSCDIMG = $localOSCDIMGPath
}

# Crear marca de tiempo para el nombre del archivo ISO
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$isoName = "tiny10_$timestamp.iso"
$isoPath = Join-Path $PSScriptRoot $isoName

Write-Host "Generando archivo ISO en: $isoPath"
Write-Host "Este proceso puede tomar varios minutos..."

# Crear el ISO usando oscdimg
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny10\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny10\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny10" "$isoPath"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nCreacion del ISO completada exitosamente!"
    Write-Host "El archivo ISO ha sido creado en: $isoPath"
} else {
    Write-Error "Error al crear el archivo ISO. Codigo de error: $LASTEXITCODE"
    exit 1
}

# Limpieza
Write-Host "`nRealizando limpieza..."
Remove-Item -Path "$ScratchDisk\tiny10" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null

Write-Host "`nProceso completado exitosamente."
Write-Host "El archivo ISO se encuentra en: $isoPath"
Write-Host "El registro del proceso se puede encontrar en: $PSScriptRoot\tiny10.log"

Stop-Transcript