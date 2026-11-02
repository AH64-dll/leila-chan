# Launch the pinned Godot binary (game/.godot-version).
# The binary is a local artifact: D:\lila\tools\godot\, see README "Local artifacts".
# Override with $env:LEILA_GODOT
$Pin = (Get-Content "$PSScriptRoot/../game/.godot-version").Trim()
$Godot = if ($env:LEILA_GODOT) { $env:LEILA_GODOT } else { "D:/lila/tools/godot/Godot_v${Pin}_win64.exe" }
if (-not (Test-Path $Godot)) {
    Write-Error "godot.ps1: $Godot not found - see README 'Local artifacts'"
    exit 1
}
& $Godot @args
exit $LASTEXITCODE
