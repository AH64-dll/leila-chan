# Run the full GDScript check suite headless (P0.06):
#   1) gdlint over game/        (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) godot --import           (rebuilds the class cache; needed on a fresh checkout)
#   3) gdUnit4 suite res://tests (vendored addon, via tools/godot.ps1 / $env:LEILA_GODOT)
# Needs dev deps for step 1: pip install -r requirements-dev.txt
# Exits non-zero if lint or any test fails; every failure is reported before exiting.

$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
$failed = $false

Write-Host "== gdlint game/ =="
if (Get-Command gdlint -ErrorAction SilentlyContinue) {
	gdlint game/
	if ($LASTEXITCODE -ne 0) { $failed = $true }
} else {
	Write-Host "test.ps1: gdlint not found - install dev deps: pip install -r requirements-dev.txt"
	$failed = $true
}

Write-Host "== godot --headless --path game --import =="
& (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game --import
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "== gdUnit4 (res://tests) =="
# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6 refuses
# headless unless told (UI input events don't work headless — keep tests logic-only).
& (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game `
	-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd `
	-a res://tests -c --ignoreHeadlessMode
if ($LASTEXITCODE -ne 0) { $failed = $true }

Pop-Location
if ($failed) {
	Write-Host "test.ps1: FAILED"
	exit 1
}
Write-Host "test.ps1: all checks passed"
exit 0
