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
Start-Transcript -Path "$PSScriptRoot\tiny10.log"

$Host.UI.RawUI.WindowTitle = "Creador de imagen Tiny10"
Clear-Host
Write-Host "Bienvenido al creador de imagen Tiny10! Version: 04-02-2025"

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
Set-ItemProperty -Path "$DiscoTrabajo\tiny10\sources\install.esd" -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
Remove-Item "$DiscoTrabajo\tiny10\sources\install.esd" -ErrorAction SilentlyContinue
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
    Write-Warning "No se pudo modificar el atributo de solo lectura. Continuando..."
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
    $prefijosPaquetes | Where-Object { $nombrePaquete -like "$_*" }
}

foreach ($paquete in $paquetesEliminar) {
    Write-Host "Eliminando paquete: $paquete"
    & dism "/image:$($DiscoTrabajo)\directoriotemporal" '/Remove-ProvisionedAppxPackage' "/PackageName:$paquete"
}

Write-Host "Eliminando Edge..."
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Eliminando OneDrive..."
& takeown "/f" "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" | Out-Null
& icacls "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" "/grant" "$($adminGroup.Value):(F)" "/T" "/C" | Out-Null
Remove-Item -Path "$DiscoTrabajo\directoriotemporal\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue

Write-Host "Eliminacion completada!"
Start-Sleep -Seconds 2
Clear-Host

Write-Host "Cargando registro..."
$registros = @{
    'COMPONENTS' = "$DiscoTrabajo\directoriotemporal\Windows\System32\config\COMPONENTS"
    'DEFAULT' = "$DiscoTrabajo\directoriotemporal\Windows\System32\config\default"
    'NTUSER' = "$DiscoTrabajo\directoriotemporal\Users\Default\ntuser.dat"
    'SOFTWARE' = "$DiscoTrabajo\directoriotemporal\Windows\System32\config\SOFTWARE"
    'SYSTEM' = "$DiscoTrabajo\directoriotemporal\Windows\System32\config\SYSTEM"
}

foreach ($reg in $registros.GetEnumerator()) {
    $proceso = Start-Process "reg" -ArgumentList "load", "HKLM\z$($reg.Key)", "$($reg.Value)" -PassThru -Wait
    if ($proceso.ExitCode -ne 0) {
        Write-Warning "Error al cargar registro $($reg.Key). Continuando..."
    }
}

Write-Host "Deshabilitando aplicaciones patrocinadas..."
$regKeys = @{
    'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{
        'OemPreInstalledAppsEnabled' = 0
        'PreInstalledAppsEnabled' = 0
        'SilentInstalledAppsEnabled' = 0
    }
    'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' = @{
        'DisableWindowsConsumerFeatures' = 1
    }
}

foreach ($path in $regKeys.Keys) {
    foreach ($value in $regKeys[$path].GetEnumerator()) {
        $proceso = Start-Process "reg" -ArgumentList "add", $path, "/v", $value.Key, "/t", "REG_DWORD", "/d", $value.Value, "/f" -PassThru -Wait
        if ($proceso.ExitCode -ne 0) {
            Write-Warning "Error al modificar registro $path\$($value.Key). Continuando..."
        }
    }
}

Write-Host "Deshabilitando telemetria..."
$telemetryKeys = @{
    'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' = @{
        'Enabled' = 0
    }
    'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' = @{
        'TailoredExperiencesWithDiagnosticDataEnabled' = 0
    }
    'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' = @{
        'AllowTelemetry' = 0
    }
}

foreach ($path in $telemetryKeys.Keys) {
    foreach ($value in $telemetryKeys[$path].GetEnumerator()) {
        $proceso = Start-Process "reg" -ArgumentList "add", $path, "/v", $value.Key, "/t", "REG_DWORD", "/d", $value.Value, "/f" -PassThru -Wait
        if ($proceso.ExitCode -ne 0) {
            Write-Warning "Error al modificar registro $path\$($value.Key). Continuando..."
        }
    }
}

# Servicios a deshabilitar (manteniendo servicios de Xbox)
$serviciosADeshabilitar = @(
    "DiagTrack",                # Telemetria de Windows
    "dmwappushservice",         # Servicio de mensajes WAP Push
    "WSearch"                   # Busqueda de Windows
)

foreach ($servicio in $serviciosADeshabilitar) {
    $proceso = Start-Process "reg" -ArgumentList "add", "HKLM\zSYSTEM\ControlSet001\Services\$servicio", "/v", "Start", "/t", "REG_DWORD", "/d", "4", "/f" -PassThru -Wait
    if ($proceso.ExitCode -ne 0) {
        Write-Warning "Error al deshabilitar servicio $servicio. Continuando..."
    }
}

Write-Host "Descargando registro..."
$registros = @('COMPONENTS', 'DEFAULT', 'NTUSER', 'SOFTWARE', 'SYSTEM')
foreach ($reg in $registros) {
    $proceso = Start-Process "reg" -ArgumentList "unload", "HKLM\z$reg" -PassThru -Wait
    if ($proceso.ExitCode -ne 0) {
        Write-Warning "Error al descargar registro $reg. Continuando..."
    }
    Start-Sleep -Seconds 1
}

Write-Host "Limpiando imagen..."
try {
    Repair-WindowsImage -Path "$DiscoTrabajo\directoriotemporal" -StartComponentCleanup -ResetBase
    Write-Host "Limpieza completada."
} catch {
    Write-Warning "Error durante la limpieza de la imagen. Continuando..."
}

Write-Host "Desmontando imagen..."
try {
    Dismount-WindowsImage -Path "$DiscoTrabajo\directoriotemporal" -Save
    Write-Host "Imagen desmontada exitosamente."
} catch {
    Write-Warning "Error al desmontar la imagen. Intentando forzar el desmontaje..."
    try {
        Dismount-WindowsImage -Path "$DiscoTrabajo\directoriotemporal" -Save -Force
    } catch {
        Write-Error "Error critico al desmontar la imagen. El proceso no puede continuar."
        exit 1
    }
}

Write-Host "Exportando imagen..."
try {
    Export-WindowsImage -SourceImagePath "$DiscoTrabajo\tiny10\sources\install.wim" -SourceIndex $indice -DestinationImagePath "$DiscoTrabajo\tiny10\sources\install2.wim" -CompressionType Fast
    Remove-Item -Path "$DiscoTrabajo\tiny10\sources\install.wim" -Force -ErrorAction SilentlyContinue
    Rename-Item -Path "$DiscoTrabajo\tiny10\sources\install2.wim" -NewName "install.wim"
} catch {
    Write-Error "Error al exportar la imagen. El proceso no puede continuar."
    exit 1
}

# Procesar boot.wim y generar ISO
Write-Host "Procesando imagen boot.wim..."
New-Item -ItemType Directory -Force -Path "$DiscoTrabajo\boottemp" > $null
Mount-WindowsImage -ImagePath "$DiscoTrabajo\tiny10\sources\boot.wim" -Index 2 -Path "$DiscoTrabajo\boottemp"

# Aplicar cambios a boot.wim
Write-Host "Aplicando optimizaciones a boot.wim..."
$serviciosBootWim = @(
    "DiagTrack",
    "dmwappushservice"
)

foreach ($servicio in $serviciosBootWim) {
    try {
        Disable-WindowsOptionalFeature -Path "$DiscoTrabajo\boottemp" -FeatureName $servicio -Remove -NoRestart -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "No se pudo deshabilitar el servicio $servicio en boot.wim. Continuando..."
    }
}

# Desmontar y guardar boot.wim
Write-Host "Guardando cambios en boot.wim..."
try {
    Dismount-WindowsImage -Path "$DiscoTrabajo\boottemp" -Save
} catch {
    Write-Warning "Error al desmontar boot.wim. Intentando forzar el desmontaje..."
    try {
        Dismount-WindowsImage -Path "$DiscoTrabajo\boottemp" -Save -Force
    } catch {
        Write-Error "Error critico al desmontar boot.wim."
        exit 1
    }
}
Remove-Item -Path "$DiscoTrabajo\boottemp" -Recurse -Force -ErrorAction SilentlyContinue

# Verificar oscdimg.exe
Write-Host "Verificando herramientas necesarias..."
$oscdimgPath = Join-Path $PSScriptRoot "oscdimg.exe"

if (-not (Test-Path $oscdimgPath)) {
    Write-Error "ERROR: No se encuentra oscdimg.exe en el directorio actual ($PSScriptRoot)"
    Write-Host "Por favor, asegurese de que oscdimg.exe este en el mismo directorio que este script."
    exit 1
}

# Preparar nombre y ruta del ISO
$fechaHora = Get-Date -Format "yyyyMMdd-HHmm"
$isoNombre = "tiny10_$fechaHora.iso"
$isoRuta = Join-Path $PSScriptRoot $isoNombre

Write-Host "Generando archivo ISO en: $isoRuta"
Write-Host "Este proceso puede tomar varios minutos..."

# Crear el ISO usando oscdimg
try {
    & $oscdimgPath -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$DiscoTrabajo\tiny10\boot\etfsboot.com"#pEF,e,b"$DiscoTrabajo\tiny10\efi\microsoft\boot\efisys.bin" "$DiscoTrabajo\tiny10" "$isoRuta"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nCreacion de ISO completada exitosamente!"
        Write-Host "El archivo ISO se ha creado en: $isoRuta"
    } else {
        Write-Error "Error al crear el archivo ISO. Codigo de error: $LASTEXITCODE"
    }
} catch {
    Write-Error "Error inesperado al crear el ISO: $($_.Exception.Message)"
    exit 1
}

# Limpiar archivos temporales
Write-Host "`nLimpiando archivos temporales..."
Remove-Item -Path "$DiscoTrabajo\tiny10" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$DiscoTrabajo\directoriotemporal" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$DiscoTrabajo\boottemp" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`nProceso finalizado exitosamente."
Write-Host "El archivo ISO se encuentra en: $isoRuta"
Write-Host "El registro del proceso se encuentra en: $PSScriptRoot\tiny10.log"

Stop-Transcript