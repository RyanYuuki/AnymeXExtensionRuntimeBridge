Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step { param($msg) Write-Host "`n  ► $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  ✔  $msg" -ForegroundColor Green }
function Write-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║      AnymeX Desktop Runtime — Windows Setup  ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

$DocsDir    = [Environment]::GetFolderPath('MyDocuments')
$BaseDir    = Join-Path $DocsDir 'AnymeX'
$ToolsDir   = Join-Path $BaseDir 'Tools'
$JreDir     = Join-Path $ToolsDir 'jre'
$Dex2JarDir = Join-Path $ToolsDir 'dex-tools-v2.4'
$JarDest    = Join-Path $ToolsDir 'anymex_desktop_runtime.jar'

$JarUrl     = 'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/latest/download/anymex_desktop_runtime.jar'
$JreUrl     = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_windows_hotspot_17.0.12_7.zip'
$Dex2JarUrl = 'https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip'

function Download-File {
    param([string]$Url, [string]$Dest, [string]$Label)
    Write-Step "Downloading $Label..."
    $tmp = "$Dest.tmp"
    try {
        $req  = [System.Net.HttpWebRequest]::Create($Url)
        $req.AllowAutoRedirect = $true
        $res  = $req.GetResponse()
        $total = $res.ContentLength
        $stream = $res.GetResponseStream()
        $out  = [System.IO.File]::Create($tmp)
        $buf  = New-Object byte[] 81920
        $read = 0
        $down = 0
        $sw   = [System.Diagnostics.Stopwatch]::StartNew()

        while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $read)
            $down += $read
            if ($sw.ElapsedMilliseconds -gt 250) {
                $mb = [math]::Round($down / 1MB, 1)
                if ($total -gt 0) {
                    $pct = [math]::Round($down * 100 / $total, 0)
                    $tot = [math]::Round($total / 1MB, 1)
                    Write-Host "`r    $pct% — ${mb} MB / ${tot} MB   " -NoNewline
                } else {
                    Write-Host "`r    ${mb} MB downloaded   " -NoNewline
                }
                $sw.Restart()
            }
        }
        Write-Host ""
        $out.Close(); $stream.Close(); $res.Close()
        Move-Item -Force $tmp $Dest
        $mb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
        Write-OK "$Label downloaded (${mb} MB)"
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        throw "Failed to download ${Label}: $_"
    }
}

function Expand-Zip {
    param([string]$ZipPath, [string]$DestDir)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestDir)
}

function Flatten-SingleSubfolder {
    param([string]$Dir)
    $children = Get-ChildItem $Dir
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        $inner = $children[0].FullName
        Get-ChildItem $inner | ForEach-Object { Move-Item $_.FullName $Dir -Force }
        Remove-Item $inner -Force -Recurse
    }
}

Write-Banner

$ForceJar     = $args -contains '--force-jar'
$ForceJre     = $args -contains '--force-jre'
$ForceDex2jar = $args -contains '--force-dex2jar'
$ForceAll     = $args -contains '--force'
if ($ForceAll) { $ForceJar = $ForceJre = $ForceDex2jar = $true }

Write-Host "  Destination : $BaseDir" -ForegroundColor DarkGray

foreach ($d in @($ToolsDir, $JreDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

if ($ForceJar -or -not (Test-Path $JarDest)) {
    if (Test-Path $JarDest) { Remove-Item $JarDest -Force }
    Download-File -Url $JarUrl -Dest $JarDest -Label 'Bridge JAR'
} else {
    $sz = [math]::Round((Get-Item $JarDest).Length / 1MB, 1)
    Write-OK "Bridge JAR already present (${sz} MB) — use --force-jar to re-download"
}

$jrePresent = Test-Path (Join-Path $JreDir 'bin\java.exe')
if ($ForceJre -or -not $jrePresent) {
    if (Test-Path $JreDir) { Remove-Item $JreDir -Recurse -Force }
    New-Item -ItemType Directory -Path $JreDir -Force | Out-Null
    $jreZip = Join-Path $ToolsDir 'jre_archive.zip'
    Download-File -Url $JreUrl -Dest $jreZip -Label 'Java 17 JRE'
    Write-Step 'Extracting Java 17 JRE...'
    Expand-Zip -ZipPath $jreZip -DestDir $JreDir
    Flatten-SingleSubfolder $JreDir
    Remove-Item $jreZip -Force
    Write-OK 'Java 17 JRE extracted'
} else {
    Write-OK 'Java 17 JRE already present — use --force-jre to re-download'
}

$d2jBat = Join-Path $Dex2JarDir 'd2j-dex2jar.bat'
if ($ForceDex2jar -or -not (Test-Path $d2jBat)) {
    if (Test-Path $Dex2JarDir) { Remove-Item $Dex2JarDir -Recurse -Force }
    $d2jZip = Join-Path $ToolsDir 'dex2jar.zip'
    Download-File -Url $Dex2JarUrl -Dest $d2jZip -Label 'dex2jar'
    Write-Step 'Extracting dex2jar...'
    Expand-Zip -ZipPath $d2jZip -DestDir $ToolsDir
    Remove-Item $d2jZip -Force
    Write-OK 'dex2jar extracted'
} else {
    Write-OK 'dex2jar already present — use --force-dex2jar to re-download'
}

Write-Host ""
Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  ✔  All done! Open AnymeX — runtime is ready."  -ForegroundColor Green
Write-Host "  ═══════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Files placed under: $ToolsDir" -ForegroundColor DarkGray
Write-Host ""
