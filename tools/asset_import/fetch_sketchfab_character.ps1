param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Uid = "2dcc08114c274ad69d746ceeb692ad4b",
    [string]$Godot = "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"

# Repo root = ...\tools\asset_import -> ../..
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dest = Join-Path $repo "game\assets\models\characters"
$tmp = Join-Path $env:TEMP ("qbo_sketchfab_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $dest, $tmp | Out-Null

Write-Host "[1/5] Requesting download link for $Uid ..."
$headers = @{ Authorization = "Token $Token" }
try {
    $info = Invoke-RestMethod -Uri "https://api.sketchfab.com/v3/models/$Uid/download" -Headers $headers
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($code -eq 401) { throw "Invalid or revoked token (401)." }
    if ($code -eq 403) { throw "This account cannot download the model (403) - download may be disabled." }
    throw
}

$url = $null
if ($info.gltf -and $info.gltf.url) { $url = $info.gltf.url }
elseif ($info.glb -and $info.glb.url) { $url = $info.glb.url }
elseif ($info.source -and $info.source.url) { $url = $info.source.url }
if (-not $url) { throw "API returned no glTF/GLB link. Model may only allow source download." }

Write-Host "[2/5] Downloading archive ..."
$zip = Join-Path $tmp "model.zip"
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host ("      " + [math]::Round((Get-Item $zip).Length / 1MB, 2) + " MB")

Write-Host "[3/5] Extracting ..."
Expand-Archive -Path $zip -DestinationPath $tmp -Force

$gltf = Get-ChildItem -Path $tmp -Recurse -File -Include *.gltf, *.glb |
    Sort-Object @{ Expression = { if ($_.Name -eq "scene.gltf") { 0 } elseif ($_.Extension -eq ".glb") { 1 } else { 2 } } } |
    Select-Object -First 1
if (-not $gltf) { throw "Archive has no .gltf/.glb file." }

Write-Host "[4/5] Copying into $dest"
# Remove old model files (keep our README) so the new model wins.
Get-ChildItem -Path $dest -Force | Where-Object { $_.Name -ne "README.md" } | Remove-Item -Recurse -Force

$srcDir = $gltf.Directory.FullName
Copy-Item -Path (Join-Path $srcDir "*") -Destination $dest -Recurse -Force
Remove-Item (Join-Path $dest "model.zip") -ErrorAction SilentlyContinue
$target = Join-Path $dest ("player" + $gltf.Extension)
Move-Item -Path (Join-Path $dest $gltf.Name) -Destination $target -Force
Write-Host ("      -> " + $target)

# Print animation names and bone count for a quick sanity check.
$json = $null
if ($gltf.Extension -eq ".gltf") {
    $json = Get-Content -Raw $target | ConvertFrom-Json
} else {
    $bytes = [System.IO.File]::ReadAllBytes($target)
    $len = [BitConverter]::ToUInt32($bytes, 12)
    $json = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $len) | ConvertFrom-Json
}
$anims = @($json.animations | ForEach-Object { $_.name })
$bones = if ($json.skins) { $json.skins[0].joints.Count } else { 0 }
Write-Host ("      animations (" + $anims.Count + "): " + ($anims -join ", "))
Write-Host ("      bones: " + $bones)

Write-Host "[5/5] Importing with Godot ..."
Push-Location $repo
try {
    & $Godot --headless --path game --editor --quit | Out-Null
} finally {
    Pop-Location
}

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host "Done. Run: $Godot --path game -- --hud-test"
