# Habilitar depuracion si es necesario
#Set-PSDebug -Trace 1

param (
    [ValidatePattern('^[c-zC-Z]$')]
    [string]$DiscoTrabajo
)

if (-not $DiscoTrabajo) {
    $DiscoTrabajo = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $DiscoTrabajo = $DiscoTrabajo + ":"
}

Write-Output "Disco de trabajo establecido en $DiscoTrabajo"

# Verificar politica de ejecucion de PowerShell
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "La politica actual de ejecucion de PowerShell esta configurada como Restricted, lo que impide la ejecucion de scripts. Desea cambiarla a RemoteSigned? (si/no)"
    $respuesta = Read-Host
    if ($respuesta -eq 'si') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "El script no puede ejecutarse sin cambiar la politica de ejecucion. Saliendo..."
        exit
    }
}

# Verificar y ejecutar como administrador
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$miWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$miWindowsPrincipal = new-object System.Security.Principal.WindowsPrincipal($miWindowsID)
$rolAdmin = [System.Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $miWindowsPrincipal.IsInRole($rolAdmin)) {
    Write-Host "Reiniciando el creador de imagen Tiny10 como administrador en una nueva ventana, puede cerrar esta."
    $nuevoProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
    $nuevoProcess.Arguments = $myInvocation.MyCommand.Definition
    $nuevoProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($nuevoProcess)
    exit
}

# Iniciar registro y preparar ventana
Start-Transcript -Path "$DiscoTrabajo\tiny10.log"

$Host.UI.RawUI.WindowTitle = "Creador de imagen Tiny10"
Clear-Host
Write-Host "Bienvenido al creador de imagen Tiny10! Version: 04-02-25"

$arquitecturaSistema = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$DiscoTrabajo\tiny10\sources" | Out-Null

do {
    $LetraUnidad = Read-Host "Por favor, ingrese la letra de la unidad donde esta montada la imagen de Windows 10"
    if ($LetraUnidad -match '^[c-zC-Z]$') {
        $LetraUnidad = $LetraUnidad + ":"
        Write-Output "Letra de unidad establecida en $LetraUnidad"
    } else {
        Write-Output "Letra de unidad invalida. Por favor, ingrese una letra entre C y Z."
    }
} while ($LetraUnidad -notmatch '^[c-zC-Z]:$')

# Verificar archivos de instalacion
if ((Test-Path "$LetraUnidad\sources\boot.wim") -eq $false -or (Test-Path "$LetraUnidad\sources\install.wim") -eq $false) {
    if ((Test-Path "$LetraUnidad\sources\install.esd") -eq $true) {
        Write-Host "Se encontro install.esd, convirtiendo a install.wim..."
        Get-WindowsImage -ImagePath "$LetraUnidad\sources\install.esd"
        $indice = Read-Host "Por favor, ingrese el indice de la imagen"
        Write-Host " "
        Write-Host "Convirtiendo install.esd a install.wim. Esto puede tomar tiempo..."
        Export-WindowsImage -SourceImagePath "$LetraUnidad\sources\install.esd" -SourceIndex $indice -DestinationImagePath "$DiscoTrabajo\tiny10\sources\install.wim" -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Host "No se encuentran los archivos de instalacion de Windows en la unidad especificada."
        Write-Host "Por favor, ingrese la letra de unidad correcta."
        exit
    }
}

Write-Host "Copiando imagen de Windows..."
Copy-Item -Path "$LetraUnidad\*" -Destination "$DiscoTrabajo\tiny10" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$DiscoTrabajo\tiny10\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$DiscoTrabajo\tiny10\sources\install.esd" > $null 2>&1
Write-Host "Copia completada!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Obteniendo informacion de la imagen:"
Get-WindowsImage -ImagePath "$DiscoTrabajo\tiny10\sources\install.wim"
$indice = Read-Host "Por favor, ingrese el indice de la imagen"

Write-Host "Montando imagen de Windows. Esto puede tomar tiempo..."
$rutaWim = "$DiscoTrabajo\tiny10\sources\install.wim"
& takeown "/F" $rutaWim 
& icacls $rutaWim "/grant" "$($adminGroup.Value):(F)"

try {
    Set-ItemProperty -Path $rutaWim -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # Suprimimos el error si ocurre
}

New-Item -ItemType Directory -Force -Path "$DiscoTrabajo\directoriotemporal" > $null
Mount-WindowsImage -ImagePath "$DiscoTrabajo\tiny10\sources\install.wim" -Index $indice -Path "$DiscoTrabajo\directoriotemporal"

# Obtener informacion del idioma del sistema
$infoIdioma = & dism /Get-Intl "/Image:$($DiscoTrabajo)\directoriotemporal"
$lineaIdioma = $infoIdioma -split '\n' | Where-Object { $_ -match 'Idioma predeterminado de la interfaz de usuario del sistema : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($lineaIdioma) {
    $codigoIdioma = $Matches[1]
    Write-Host "Codigo de idioma del sistema: $codigoIdioma"
} else {
    Write-Host "No se encontro el codigo de idioma."
}

Write-Host "Montaje completado. Procediendo a eliminar aplicaciones..."

# Lista de aplicaciones a eliminar (manteniendo Xbox)
$paquetes = & dism "/image:$($DiscoTrabajo)\directoriotemporal" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'Nombre del paquete : (.*)') {
            $matches[1]
        }
    }

$prefijosPaquetes = @(
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

$paquetesEliminar = $paquetes | Where-Object {
    $nombrePaquete = $_
    $prefijosPaquetes -contains ($prefijosPaquetes | Where-Object { $nombrePaquete -like "$_*" })
}

foreach ($paquete in $paquetesEliminar) {
    & dism "/image:$($DiscoTrabajo)\directoriotemporal" '/Remove-ProvisionedAppxPackage' "/PackageName:$paquete"
}

Write-Host "Eliminando Edge..."
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null

Write-Host "Eliminando OneDrive..."
& takeown "/f" "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" | Out-Null
& icacls "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" "/grant" "$($adminGroup.Value):(F)" "/T" "/C" | Out-Null
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" -Force | Out-Null

Write-Host "Eliminacion completada!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Cargando registro..."
reg load HKLM\zCOMPONENTS "$DiscoTrabajo\directoriotemporal\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$DiscoTrabajo\directoriotemporal\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$DiscoTrabajo\directoriotemporal\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$DiscoTrabajo\directoriotemporal\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$DiscoTrabajo\directoriotemporal\Windows\System32\config\SYSTEM" | Out-Null

Write-Host "Deshabilitando aplicaciones patrocinadas..."
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f | Out-Null

Write-Host "Deshabilitando telemetria..."
& reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f | Out-Null
& reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f | Out-Null

# Servicios a deshabilitar (manteniendo servicios de Xbox)
$serviciosADeshabilitar = @(
    "DiagTrack",                # Telemetria de Windows
    "dmwappushservice",         # Servicio de mensajes WAP Push
    "WSearch"                   # Busqueda de Windows
)

foreach ($servicio in $serviciosADeshabilitar) {
    & reg add "HKLM\zSYSTEM\ControlSet001\Services\$servicio" /v "Start" /t REG_DWORD /d 4 /f | Out-Null
}

Write-Host "Descargando registro..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Host "Limpiando imagen..."
Repair-WindowsImage -Path "$DiscoTrabajo\directoriotemporal" -StartComponentCleanup -ResetBase
Write-Host "Limpieza completada."

Write-Host "Desmontando imagen..."
Dismount-WindowsImage -Path "$DiscoTrabajo\directoriotemporal" -Save

Write-Host "Exportando imagen..."
Export-WindowsImage -SourceImagePath "$DiscoTrabajo\tiny10\sources\install.wim" -SourceIndex $indice -DestinationImagePath "$DiscoTrabajo\tiny10\sources\install2.wim" -CompressionType Fast
Remove-Item -Path "$DiscoTrabajo\tiny10\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$DiscoTrabajo\tiny10\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Host "Procesando imagen boot.wim..."

# Creación de ISO

Write-Host "Verificando la presencia de oscdimg.exe..."
$oscdimgPath = Join-Path $PSScriptRoot "oscdimg.exe"

if (-not (Test-Path $oscdimgPath)) {
    Write-Host "ERROR: No se encuentra oscdimg.exe en el directorio actual."
    Write-Host "Por favor, asegurese de que oscdimg.exe este en el mismo directorio que este script."
    exit
}

Write-Host "Creando archivo ISO..."
$fechaHora = Get-Date -Format "yyyyMMdd-HHmm"
$isoNombre = "tiny10_$fechaHora.iso"
$isoRuta = Join-Path $DiscoTrabajo $isoNombre

# Crear el ISO usando oscdimg
& $oscdimgPath -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$DiscoTrabajo\tiny10\boot\etfsboot.com"#pEF,e,b"$DiscoTrabajo\tiny10\efi\microsoft\boot\efisys.bin" "$DiscoTrabajo\tiny10" "$isoRuta"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nProceso completado exitosamente!"
    Write-Host "El archivo ISO ha sido creado en: $isoRuta"
} else {
    Write-Host "`nError al crear el archivo ISO. Codigo de error: $LASTEXITCODE"
}

# Limpiar archivos temporales
Write-Host "`nLimpiando archivos temporales..."
Remove-Item -Path "$DiscoTrabajo\tiny10" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$DiscoTrabajo\directoriotemporal" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Proceso finalizado."

# Stop the transcript
Stop-Transcript

exit