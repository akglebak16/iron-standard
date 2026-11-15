$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$toolRoot = Join-Path $workspaceRoot 'dist/godot/native-tools'
New-Item -ItemType Directory -Force $toolRoot | Out-Null
$dependencies = Get-Content (Join-Path $PSScriptRoot 'native_dependencies.json') -Raw | ConvertFrom-Json
foreach ($dependency in $dependencies) {
    $archivePath = Join-Path $toolRoot $dependency.archive
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Host "Downloading $($dependency.directory)"
        Invoke-WebRequest $dependency.url -OutFile $archivePath
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $dependency.sha256) {
        throw "SHA256 mismatch: $archivePath; no extraction performed"
    }
    $destination = Join-Path $toolRoot $dependency.directory
    if (-not (Test-Path -LiteralPath (Join-Path $destination $dependency.probe))) {
        $extractTo = if ($dependency.flat) { $destination } else { $toolRoot }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractTo -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destination $dependency.probe))) { throw "Incomplete tool: $destination" }
}
Write-Host 'Pinned native toolchain ready (workspace only)'
