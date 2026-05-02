@echo off
setlocal enabledelayedexpansion

echo ==============================
echo AnymeX Runtime Host Builder
echo ==============================
echo.

echo Script directory:
echo %~dp0
echo.

cd /d "%~dp0"

echo Running Gradle Release Build...
echo.

call gradlew assembleRelease

if errorlevel 1 (
    echo.
    echo ❌ GRADLE BUILD FAILED
    echo Press any key to exit...
    pause >nul
    exit /b 1
)

echo.
echo Gradle build finished.
echo.

echo Searching for APK...

set APK_PATH=

for /r "app\build\outputs\apk\release" %%f in (*.apk) do (
    set APK_PATH=%%f
)

if not defined APK_PATH (
    echo ❌ APK NOT FOUND
    pause
    exit /b 1
)

echo APK Found:
echo !APK_PATH!
echo.

set FINAL_APK=%~dp0anymex_runtime_host.apk

copy /Y "!APK_PATH!" "!FINAL_APK!"

if errorlevel 1 (
    echo ❌ COPY FAILED
    pause
    exit /b 1
)

echo APK Copied to:
echo !FINAL_APK!
echo.

echo Checking ADB...

adb version >nul 2>&1

if errorlevel 1 (
    echo ❌ ADB NOT FOUND IN PATH
    echo Install platform-tools or add to PATH
    pause
    exit /b 1
)

echo Listing devices...
adb devices

set DEVICE=

for /f "skip=1 tokens=1,2" %%a in ('adb devices') do (
    if "%%b"=="device" (
        set DEVICE=%%a
    )
)

if not defined DEVICE (
    echo ❌ No device connected
    pause
    exit /b 0
)

echo Device Found: !DEVICE!
echo.

echo Creating folder on device...
adb -s !DEVICE! shell mkdir -p /sdcard/AnymeX/

echo Pushing APK...
adb -s !DEVICE! push "!FINAL_APK!" /sdcard/AnymeX/

echo.
echo ✅ DONE SUCCESSFULLY
echo.

pause