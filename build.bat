@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "OUTPUT_DIR=%SCRIPT_DIR%\output"
set "DESKTOP_DEST_DIR=%USERPROFILE%\Documents\AnymeX\Tools"
set "DESKTOP_DEST_FILE=anymex_desktop_runtime.jar"

set "TARGET=%~1"
if not "%TARGET%"=="" goto handle_target

:menu
echo =======================================
echo   AnymeX Extension Runtime Builder
echo =======================================
echo.
echo   1) Android          - Build APK + ADB push
echo   2) Desktop          - Build JAR + Copy to runtime folder
echo   3) Both             - Build Android and Desktop
echo   4) Push Android     - Push current APK build via ADB
echo   5) Push Desktop     - Copy current JAR build to runtime folder
echo   6) Push Both        - Push current builds (ADB + copy)
echo   7) Clean Android    - Clean + Build APK + ADB push
echo   8) Clean Desktop    - Clean + Build JAR + Copy
echo   9) Clean Both       - Clean + Build Both
echo.
set /p "CHOICE=Choose [1-9]: "

if "%CHOICE%"=="1" set "TARGET=android"& goto handle_target
if "%CHOICE%"=="2" set "TARGET=desktop"& goto handle_target
if "%CHOICE%"=="3" set "TARGET=both"& goto handle_target
if "%CHOICE%"=="4" set "TARGET=push-android"& goto handle_target
if "%CHOICE%"=="5" set "TARGET=push-desktop"& goto handle_target
if "%CHOICE%"=="6" set "TARGET=push-both"& goto handle_target
if "%CHOICE%"=="7" set "TARGET=clean-android"& goto handle_target
if "%CHOICE%"=="8" set "TARGET=clean-desktop"& goto handle_target
if "%CHOICE%"=="9" set "TARGET=clean-both"& goto handle_target

echo [ERROR] Invalid choice: '%CHOICE%'
goto usage

:handle_target
if /i "%TARGET%"=="android" (
    call :build_android
    goto finish
)
if /i "%TARGET%"=="desktop" (
    call :build_desktop
    goto finish
)
if /i "%TARGET%"=="both" (
    call :build_android
    call :build_desktop
    goto finish
)
if /i "%TARGET%"=="push-android" (
    call :push_android
    goto finish
)
if /i "%TARGET%"=="push-desktop" (
    call :push_desktop
    goto finish
)
if /i "%TARGET%"=="push-both" (
    call :push_android
    call :push_desktop
    goto finish
)
if /i "%TARGET%"=="clean-android" (
    call :clean_android
    call :build_android
    goto finish
)
if /i "%TARGET%"=="clean-desktop" (
    call :clean_desktop
    call :build_desktop
    goto finish
)
if /i "%TARGET%"=="clean-both" (
    call :clean_android
    call :clean_desktop
    call :build_android
    call :build_desktop
    goto finish
)
if /i "%TARGET%"=="help" goto usage
if /i "%TARGET%"=="-h" goto usage
if /i "%TARGET%"=="--help" goto usage

echo [ERROR] Unknown target: '%TARGET%'

:usage
echo.
echo Usage: %~nx0 [android^|desktop^|both^|push-android^|push-desktop^|push-both^|clean-android^|clean-desktop^|clean-both]
echo.
echo   android        Build the Android runtime host APK and push via ADB
echo   desktop        Build the Desktop bridge JAR and copy to runtime folder
echo   both           Build Android and Desktop
echo   push-android   Push existing Android APK build to device via ADB
echo   push-desktop   Copy existing Desktop JAR build to runtime folder
echo   push-both      Push existing builds (ADB + copy)
echo   clean-android  Clean + build Android
echo   clean-desktop  Clean + build Desktop
echo   clean-both     Clean + build Android and Desktop
echo.
exit /b 1

:: ---------------------------------------------------------
:: Subroutines
:: ---------------------------------------------------------

:clean_android
echo.
echo =======================================
echo  Cleaning Android Runtime Host
echo =======================================
cd /d "%SCRIPT_DIR%\RuntimeBridges\Android"
call gradlew.bat clean
cd /d "%SCRIPT_DIR%"
echo [DONE] Android clean complete.
exit /b 0

:clean_desktop
echo.
echo =======================================
echo  Cleaning Desktop Bridge
echo =======================================
cd /d "%SCRIPT_DIR%\RuntimeBridges\Desktop"
call gradlew.bat clean
cd /d "%SCRIPT_DIR%"
echo [DONE] Desktop clean complete.
exit /b 0

:build_android
echo.
echo =======================================
echo  Building Android Runtime Host
echo =======================================
cd /d "%SCRIPT_DIR%\RuntimeBridges\Android"
call gradlew.bat assembleRelease
if errorlevel 1 (
    echo [ERROR] Android build failed!
    cd /d "%SCRIPT_DIR%"
    exit /b 1
)
cd /d "%SCRIPT_DIR%"

call :push_android
exit /b 0

:build_desktop
echo.
echo =======================================
echo  Building Desktop Bridge
echo =======================================
cd /d "%SCRIPT_DIR%\RuntimeBridges\Desktop"
call gradlew.bat shadowJar
if errorlevel 1 (
    echo [ERROR] Desktop build failed!
    cd /d "%SCRIPT_DIR%"
    exit /b 1
)
cd /d "%SCRIPT_DIR%"

call :push_desktop
exit /b 0

:push_android
echo.
echo =======================================
echo  Deploying Android APK
echo =======================================

set "APK_PATH="
for /r "%SCRIPT_DIR%\RuntimeBridges\Android\app\build\outputs\apk\release" %%f in (*.apk) do (
    set "APK_PATH=%%f"
)

if not defined APK_PATH (
    if exist "%SCRIPT_DIR%\RuntimeBridges\Android\anymex_runtime_host.apk" (
        set "APK_PATH=%SCRIPT_DIR%\RuntimeBridges\Android\anymex_runtime_host.apk"
    )
)

if not defined APK_PATH (
    echo [ERROR] No APK found to deploy! Please build first.
    exit /b 1
)

echo [APK] Found: !APK_PATH!
set "FINAL_APK=%SCRIPT_DIR%\RuntimeBridges\Android\anymex_runtime_host.apk"
copy /y "!APK_PATH!" "!FINAL_APK!" >nul

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy /y "!FINAL_APK!" "%OUTPUT_DIR%\anymex_runtime_host.apk" >nul
copy /y "!FINAL_APK!" "%SCRIPT_DIR%\outputs\anymex_runtime_host.apk" >nul 2>nul
echo [COPY] Copied APK to %OUTPUT_DIR%\anymex_runtime_host.apk

adb version >nul 2>&1
if errorlevel 1 (
    echo [WARN] ADB not found in PATH. Skipping ADB push.
    exit /b 0
)

set "DEVICE="
for /f "skip=1 tokens=1,2" %%a in ('adb devices') do (
    if "%%b"=="device" (
        set "DEVICE=%%a"
    )
)

if not defined DEVICE (
    echo [WARN] No ADB device connected. Skipping push to device.
    exit /b 0
)

echo [ADB] Pushing to device (!DEVICE!)...
adb -s !DEVICE! shell mkdir -p /sdcard/AnymeX/
adb -s !DEVICE! push "!FINAL_APK!" /sdcard/AnymeX/
echo [DONE] Android APK deployed successfully.
exit /b 0

:push_desktop
echo.
echo =======================================
echo  Deploying Desktop Bridge
echo =======================================

set "JAR_PATH=%SCRIPT_DIR%\RuntimeBridges\Desktop\build\libs\desktop_bridge.jar"
if not exist "!JAR_PATH!" (
    if exist "%OUTPUT_DIR%\anymex_desktop_runtime.jar" (
        set "JAR_PATH=%OUTPUT_DIR%\anymex_desktop_runtime.jar"
    )
)

if not exist "!JAR_PATH!" (
    echo [ERROR] No desktop JAR found! Please build first.
    exit /b 1
)

echo [JAR] Found: !JAR_PATH!

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy /y "!JAR_PATH!" "%OUTPUT_DIR%\anymex_desktop_runtime.jar" >nul
copy /y "!JAR_PATH!" "%SCRIPT_DIR%\outputs\anymex_desktop_runtime.jar" >nul 2>nul
echo [COPY] Copied to %OUTPUT_DIR%\anymex_desktop_runtime.jar

if not exist "%DESKTOP_DEST_DIR%" mkdir "%DESKTOP_DEST_DIR%"
copy /y "!JAR_PATH!" "%DESKTOP_DEST_DIR%\%DESKTOP_DEST_FILE%" >nul
echo [COPY] Copied to %DESKTOP_DEST_DIR%\%DESKTOP_DEST_FILE%

set "LOCAL_RUNTIME=%USERPROFILE%\Documents\AnymeX\Runtime"
if exist "%USERPROFILE%\Documents\AnymeX" (
    if not exist "!LOCAL_RUNTIME!" mkdir "!LOCAL_RUNTIME!" 2>nul
    copy /y "!JAR_PATH!" "!LOCAL_RUNTIME!\%DESKTOP_DEST_FILE%" >nul 2>nul
)

echo [DONE] Desktop bridge deployed successfully.
exit /b 0

:finish
echo.
echo =======================================
echo  [DONE] All tasks completed!
echo =======================================
exit /b 0
