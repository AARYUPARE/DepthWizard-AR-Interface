[CmdletBinding()]
param(
    [string]$ProjectsDirectory = "$env:USERPROFILE\Documents\DepthWizard-AR-Exports",
    [ValidateRange(1,65535)][int]$Port = 8765
)
$ErrorActionPreference = "Stop"
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw "Python 3.10+ is required. Install Python and enable 'Add Python to PATH'." }
$version = & python -c "import sys; print('%d.%d' % sys.version_info[:2])"
$parts = $version.Split('.')
if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 10)) {
    throw "Python 3.10 or newer is required. Detected $version."
}
$root = [IO.Path]::GetFullPath($ProjectsDirectory)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$server = Join-Path $PSScriptRoot "server.py"
Write-Host "Starting DepthWizard AR bridge on port $Port..." -ForegroundColor Cyan
Write-Host "When Windows Firewall asks, allow Python on Private networks only." -ForegroundColor Yellow
& python $server --root $root --port $Port
