# Script Optimizador de Windows 10 - Sistema en Vivo
# Version: 04-02-25

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
    Write-Host "Este script requiere privilegios de administrador. Reiniciando con elevacion..."
    $nuevoProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
    $nuevoProcess.Arguments = $myInvocation.MyCommand.Definition
    $nuevoProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($nuevoProcess)
    exit
}

# Iniciar registro
$fechaHora = Get-Date -Format "yyyy-MM-dd-HH-mm"
Start-Transcript -Path "$env:USERPROFILE\Desktop\windows10_optimizacion_$fechaHora.log"

# Configurar titulo de la ventana
$Host.UI.RawUI.WindowTitle = "Optimizador de Windows 10"
Clear-Host
Write-Host "Bienvenido al Optimizador de Windows 10! Version: 04-02-25"
Write-Host "ADVERTENCIA: Este script modificara configuraciones del sistema. Se recomienda crear un punto de restauracion antes de continuar."
Write-Host "Desea crear un punto de restauracion ahora? (si/no)"
$crearRestore = Read-Host

if ($crearRestore -eq 'si') {
    Enable-ComputerRestore -Drive "$env:SystemDrive"
    Checkpoint-Computer -Description "Antes de Optimizacion Windows 10" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "Punto de restauracion creado exitosamente."
}

Write-Host "`nIniciando proceso de optimizacion...`n"

# Eliminar aplicaciones preinstaladas no deseadas
Write-Host "Eliminando aplicaciones preinstaladas..."
$appsAEliminar = @(
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

foreach ($app in $appsAEliminar) {
    Write-Host "Removiendo $app"
    Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online
}

# Deshabilitar servicios no esenciales
Write-Host "`nDeshabilitando servicios no esenciales..."
$serviciosADeshabilitar = @(
    "DiagTrack",                # Telemetria de Windows
    "dmwappushservice",         # Servicio de mensajes WAP Push
    "WSearch"                   # Busqueda de Windows
)

foreach ($servicio in $serviciosADeshabilitar) {
    Write-Host "Deshabilitando servicio: $servicio"
    Stop-Service -Name $servicio -Force -ErrorAction SilentlyContinue
    Set-Service -Name $servicio -StartupType Disabled
}

# Deshabilitar telemetria y recopilacion de datos
Write-Host "`nConfigurando politicas de privacidad..."
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

# Desinstalar Edge (opcional)
Write-Host "`nDesea desinstalar Microsoft Edge? (si/no)"
$desinstalarEdge = Read-Host

if ($desinstalarEdge -eq 'si') {
    Write-Host "Desinstalando Microsoft Edge..."
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    if (Test-Path $edgePath) {
        $installerPath = Get-ChildItem -Path $edgePath -Filter "setup.exe" -Recurse | Select-Object -First 1
        if ($installerPath) {
            Start-Process -FilePath $installerPath.FullName -ArgumentList "--uninstall --system-level --force-uninstall" -Wait
        }
    }
}

# Desinstalar OneDrive (opcional)
Write-Host "`nDesea desinstalar OneDrive? (si/no)"
$desinstalarOneDrive = Read-Host

if ($desinstalarOneDrive -eq 'si') {
    Write-Host "Desinstalando OneDrive..."
    Stop-Process -Name OneDrive -ErrorAction SilentlyContinue
    Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" "/uninstall" -Wait
    Remove-Item "$env:UserProfile\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:LocalAppData\Microsoft\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:ProgramData\Microsoft OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemDrive\OneDriveTemp" -Force -Recurse -ErrorAction SilentlyContinue
}

# Limpiar archivos temporales y cache
Write-Host "`nLimpiando archivos temporales..."
Remove-Item "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Ejecutar limpieza del sistema
Write-Host "`nEjecutando limpieza del sistema..."
cleanmgr /sagerun:1

Write-Host "`nOptimizacion completada!"
Write-Host "Se ha creado un archivo de registro en el escritorio con los detalles de las operaciones realizadas."
Write-Host "Se recomienda reiniciar el sistema para aplicar todos los cambios."
Write-Host "`nDesea reiniciar el sistema ahora? (si/no)"
$reiniciar = Read-Host

if ($reiniciar -eq 'si') {
    Stop-Transcript
    Restart-Computer -Force
} else {
    Stop-Transcript
    Write-Host "Por favor, reinicie el sistema manualmente cuando le sea conveniente."
}