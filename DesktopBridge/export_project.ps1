[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ModelPath,
    [string]$ExportRoot = "$env:USERPROFILE\Documents\DepthWizard-AR-Exports",
    [string]$ElevationMode = "Relative DSM",
    [string]$Units = "relative",
    [string]$SourceImage = "",
    [string]$BlenderPath = ""
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Name)) { throw "Project name cannot be empty." }
$model = (Resolve-Path -LiteralPath $ModelPath).Path
if ([IO.Path]::GetExtension($model).ToLowerInvariant() -ne ".glb") {
    throw "DepthWizard AR expects the single-file textured GLB exported by DepthWizard. Received: $model"
}
if ($SourceImage) { $sourceResolved = (Resolve-Path -LiteralPath $SourceImage).Path }
if (-not $BlenderPath) {
    $blenderCommand = Get-Command blender -ErrorAction SilentlyContinue
    if ($blenderCommand) { $BlenderPath = $blenderCommand.Source }
}
if (-not $BlenderPath -or -not (Test-Path -LiteralPath $BlenderPath)) {
    throw "Blender 4.2+ is required for GLB-to-USDZ conversion. Add blender.exe to PATH or pass -BlenderPath."
}
$BlenderPath = (Resolve-Path -LiteralPath $BlenderPath).Path
$projectId = [guid]::NewGuid().ToString("N")
$exportRootResolved = [IO.Path]::GetFullPath($ExportRoot)
New-Item -ItemType Directory -Force -Path $exportRootResolved | Out-Null
$projectDirectory = Join-Path $exportRootResolved $projectId
New-Item -ItemType Directory -Force -Path $projectDirectory | Out-Null
$targetModel = Join-Path $projectDirectory "model.usdz"
$converter = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Tools\convert_glb_to_usdz.py"))
$validator = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Tools\validate_project.py"))
try {
    Write-Host "Converting the DepthWizard GLB to a USDZ companion for RealityKit..." -ForegroundColor Cyan
    & $BlenderPath --background --factory-startup --python $converter -- --input $model --output $targetModel
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $targetModel)) {
        throw "Blender USDZ conversion failed. Check the Blender output above."
    }

    # Preserve the original desktop export for traceability; the iPad downloads model.usdz.
    Copy-Item -LiteralPath $model -Destination (Join-Path $projectDirectory "source.glb")
    $manifest = [ordered]@{
        id = $projectId
        name = $Name.Trim()
        description = "Exported from DepthWizard Desktop for iPad AR viewing"
        createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        modelFile = "model.usdz"
        modelFormat = "usdz"
        sourceModelFile = "source.glb"
        sourceImage = $null
        elevationMode = $ElevationMode
        units = $Units
    }
    if ($SourceImage) {
        $sourceName = [IO.Path]::GetFileName($sourceResolved)
        Copy-Item -LiteralPath $sourceResolved -Destination (Join-Path $projectDirectory $sourceName)
        $manifest.sourceImage = $sourceName
    }
    $manifestPath = Join-Path $projectDirectory "project.json"
    $manifestJson = $manifest | ConvertTo-Json -Depth 5
    # UTF-8 without BOM so Swift's JSONDecoder can read this manifest on iPad.
    [IO.File]::WriteAllText($manifestPath, $manifestJson, [Text.UTF8Encoding]::new($false))

    $pythonCommand = Get-Command python -ErrorAction Stop
    & $pythonCommand.Source $validator $projectDirectory
    if ($LASTEXITCODE -ne 0) { throw "Export validation failed." }
}
catch {
    Remove-Item -LiteralPath $projectDirectory -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

Write-Host "`nDepthWizard AR project created:" -ForegroundColor Green
Write-Host $projectDirectory
Write-Host "The source GLB is preserved; the iPad companion is model.usdz."
Write-Host "Start DesktopBridge\start_sync_server.ps1 to make it available on your iPad."
