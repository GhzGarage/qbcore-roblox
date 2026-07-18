$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PinnedRojoPath = Join-Path $env:LOCALAPPDATA "Programs\Rojo\7.7.0\rojo.exe"
$Rojo = Get-Command rojo -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $PinnedRojoPath) {
    $RojoPath = $PinnedRojoPath
} elseif ($Rojo) {
    $RojoPath = $Rojo.Source
} else {
    $PackageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $RojoPath = Get-ChildItem -Path $PackageRoot -Filter rojo.exe -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $RojoPath) {
    throw "Could not find rojo.exe. Install Rojo 7.7.0 from the official GitHub release."
}

$RojoVersion = (& $RojoPath --version).Trim()
if ($RojoVersion -ne "Rojo 7.7.0") {
    throw "Expected Rojo 7.7.0, but found $RojoVersion at $RojoPath"
}

Push-Location $ProjectRoot
try {
    & $RojoPath serve default.project.json --port 34872
} finally {
    Pop-Location
}
