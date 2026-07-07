$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Rojo = Get-Command rojo -ErrorAction SilentlyContinue

if ($Rojo) {
    $RojoPath = $Rojo.Source
} else {
    $PackageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $RojoPath = Get-ChildItem -Path $PackageRoot -Filter rojo.exe -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $RojoPath) {
    throw "Could not find rojo.exe. Install Rojo with: winget install --id Rojo.Rojo -e"
}

Push-Location $ProjectRoot
try {
    & $RojoPath serve default.project.json --port 34872
} finally {
    Pop-Location
}
