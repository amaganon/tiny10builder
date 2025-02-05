# Tiny10 Builder [English]

## Project Origin and Adaptation

This project represents an adaptation of the original Tiny11 Builder project, developed by NTDEV. The adaptation focuses on providing an optimized Windows 10 ISO creation solution, specifically designed for users who prefer or need to remain on the Windows 10 platform while benefiting from similar optimizations available in Tiny11.

The original codebase, designed for Windows 11 ISOs, has been carefully modified and recalibrated to work seamlessly with Windows 10 installations. This adaptation maintains the core philosophy of the original project while incorporating specific adjustments necessary for Windows 10 compatibility, including preservation of gaming-related components and essential Windows 10 services.

Our primary goal is to provide users with a reliable tool to create streamlined Windows 10 installations while maintaining system stability and functionality. This project serves as a bridge for users who wish to optimize their Windows 10 experience using proven methodologies from the Tiny11 project.

## About Tiny10 Builder

Scripts to build a trimmed-down Windows 10 image - developed in **PowerShell**!

Tiny10 builder is a comprehensive and flexible solution that enables the creation of an optimized Windows 10 version, maintaining all essential functionalities and gaming compatibility.

This tool is designed to work with ANY Windows 10 release (specifically tested with version 22H2 Build 19045.3803), as well as ANY language or architecture. This is made possible thanks to PowerShell's advanced scripting capabilities.

Since it's written in PowerShell, you'll need to set the execution policy to `Unrestricted` to run the script. If you haven't done this before, make sure to run `Set-ExecutionPolicy unrestricted` as administrator in PowerShell before running the script, otherwise it will fail.

This script was created to automate the building of an optimized Windows 10 image, using only Microsoft utilities like DISM, without dependencies on external sources. The only executable included is **oscdimg.exe**, which is provided in the Windows ADK and is used to create bootable ISO images.

An unattended answer file is also included, used to bypass the Microsoft Account on OOBE and to deploy the image with the `/compact` flag.

It's open-source, **so feel free to add or remove anything you want!** Feedback is greatly appreciated.

## Instructions:

1. Download Windows 10 from Microsoft's website (<https://www.microsoft.com/software-download/windows10>)
2. Mount the downloaded ISO image using Windows Explorer
3. Select the drive letter where the image is mounted (letter only, no colon (:))
4. Select the Windows edition you want to use as base
5. Sit back and relax :)
6. When the image is complete, you'll find it in the folder where the script was extracted, named tiny10.iso

## Removed Components:

- Bing News
- Bing Weather
- GetHelp
- GetStarted
- Office Hub
- Solitaire
- People App
- Feedback Hub
- Maps
- Sound Recorder
- Your Phone
- Media Player
- Internet Explorer
- Edge
- OneDrive

## Preserved Components (specifically for gaming):
- All Xbox components
- Game Bar
- DirectX and related components
- Windows Gaming Services

## Additional Features:
- Telemetry deactivation
- Advertisement suppression
- Enhanced language and architecture detection
- Performance optimizations
- Base image size reduction

## Known Issues:

1. While Edge is removed, some remnants remain in Settings. However, the application itself is deleted. You can install any browser using WinGet (after updating the app using Microsoft Store). If you want Edge back, simply install it using Winget: `winget install edge`.

Note: You might need to update Winget before being able to install applications, using Microsoft Store.

2. Some Microsoft Store applications may reappear after certain updates.

3. Image size reduction may vary depending on the specific Windows 10 version used as base.

## Features to be Implemented:
- Enhanced advertisement suppression
- Improved language and architecture detection
- More flexibility in what to keep and what to delete
- Possible GUI interface
- Additional performance optimizations
- Greater service customization

## Important Notes:
1. This version maintains all gaming-related functionality intact
2. Windows updates will continue to function normally
3. All essential security features remain active
4. The resulting image is fully activatable and updatable

Thank you for trying it out and please let me know how it works for you!

---

# Tiny10 Builder [Español]

## Origen y Adaptación del Proyecto

Este proyecto representa una adaptación del proyecto original Tiny11 Builder, desarrollado por NTDEV. La adaptación se centra en proporcionar una solución optimizada para la creación de ISO de Windows 10, diseñada específicamente para usuarios que prefieren o necesitan permanecer en la plataforma Windows 10 mientras se benefician de optimizaciones similares a las disponibles en Tiny11.

El código base original, diseñado para ISOs de Windows 11, ha sido cuidadosamente modificado y recalibrado para funcionar sin problemas con instalaciones de Windows 10. Esta adaptación mantiene la filosofía central del proyecto original mientras incorpora ajustes específicos necesarios para la compatibilidad con Windows 10, incluyendo la preservación de componentes relacionados con juegos y servicios esenciales de Windows 10.

Nuestro objetivo principal es proporcionar a los usuarios una herramienta confiable para crear instalaciones optimizadas de Windows 10 mientras se mantiene la estabilidad y funcionalidad del sistema. Este proyecto sirve como puente para los usuarios que desean optimizar su experiencia en Windows 10 utilizando metodologías probadas del proyecto Tiny11.

## Acerca de Tiny10 Builder

Scripts para crear una imagen reducida de Windows 10 - ¡desarrollado en **PowerShell**!

Tiny10 builder es una solución completa y flexible que permite crear una versión optimizada de Windows 10, manteniendo todas las funcionalidades esenciales y la compatibilidad con videojuegos.

Esta herramienta está diseñada para funcionar con CUALQUIER versión de Windows 10 (específicamente probada con la versión 22H2 Build 19045.3803), así como con CUALQUIER idioma o arquitectura. Esto es posible gracias a las capacidades avanzadas de scripting de PowerShell.

Dado que está escrito en PowerShell, necesitarás establecer la política de ejecución en `Unrestricted` para poder ejecutar el script. Si no has realizado esto antes, asegúrate de ejecutar `Set-ExecutionPolicy unrestricted` como administrador en PowerShell antes de ejecutar el script, de lo contrario, fallará.

Este script fue creado para automatizar la construcción de una imagen optimizada de Windows 10, utilizando únicamente utilidades de Microsoft como DISM, sin dependencias de fuentes externas. El único ejecutable incluido es **oscdimg.exe**, que se proporciona en el Windows ADK y se utiliza para crear imágenes ISO bootables.

También se incluye un archivo de respuestas desatendido, que se utiliza para omitir la cuenta de Microsoft en OOBE y para implementar la imagen con la marca `/compact`.

Es de código abierto, **¡así que siéntete libre de agregar o eliminar cualquier cosa que desees!** La retroalimentación es muy apreciada.

## Instrucciones:

1. Descarga Windows 10 desde el sitio web de Microsoft (<https://www.microsoft.com/es-es/software-download/windows10>)
2. Monta la imagen ISO descargada usando el Explorador de Windows
3. Selecciona la letra de unidad donde está montada la imagen (solo la letra, sin dos puntos (:))
4. Selecciona la edición de Windows que deseas usar como base
5. Relájate y espera :)
6. Cuando la imagen esté completa, la encontrarás en la carpeta donde se extrajo el script, con el nombre tiny10.iso

## Elementos Eliminados:

- Bing News
- Bing Weather
- GetHelp
- GetStarted
- Office Hub
- Solitaire
- People App
- Feedback Hub
- Maps
- Sound Recorder
- Your Phone
- Media Player
- Internet Explorer
- Edge
- OneDrive

## Elementos Preservados (específicamente para gaming):
- Todos los componentes de Xbox
- Game Bar
- DirectX y componentes relacionados
- Windows Gaming Services

## Características Adicionales:
- Desactivación de telemetría
- Supresión de publicidad
- Detección mejorada de idioma y arquitectura
- Optimizaciones de rendimiento
- Reducción del tamaño de la imagen base

## Problemas Conocidos:

1. Aunque Edge se elimina, quedan algunos residuos en la Configuración. Pero la aplicación en sí está eliminada. Puedes instalar cualquier navegador usando WinGet (después de actualizar la aplicación usando Microsoft Store). Si deseas Edge de vuelta, simplemente instálalo usando Winget: `winget install edge`.

Nota: Es posible que debas actualizar Winget antes de poder instalar aplicaciones, usando Microsoft Store.

2. Algunas aplicaciones del Microsoft Store pueden reaparecer después de ciertas actualizaciones.

3. La reducción del tamaño de la imagen puede variar según la versión específica de Windows 10 utilizada como base.

## Características a Implementar:
- Mayor supresión de publicidad
- Detección mejorada de idioma y arquitectura
- Más flexibilidad en qué mantener y qué eliminar
- Posible interfaz gráfica
- Optimizaciones adicionales de rendimiento
- Mayor personalización de servicios

## Notas Importantes:
1. Esta versión mantiene toda la funcionalidad relacionada con gaming intacta
2. Las actualizaciones de Windows seguirán funcionando normalmente
3. Todas las características de seguridad esenciales se mantienen activas
4. La imagen resultante es completamente activable y actualizable

¡Gracias por probarlo y hazme saber cómo te funciona!