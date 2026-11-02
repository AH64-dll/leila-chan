# Run the full GDScript check suite headless (P0.06; hardened in P0.15):
#   1) gdlint over game/            (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) gdformat --check over game/  (config: repo-root gdformatrc; format drift gates too)
#   3) godot --import               (rebuilds the class cache; needed on a fresh checkout)
#   4) gdUnit4 suites res://tests   (vendored addon, via tools/godot.ps1 / $env:LEILA_GODOT)
#   5) standalone --script tests    (non-suite scripts at game/tests/*.gd)
# Needs dev deps for steps 1-2: pip install -r requirements-dev.txt
# Exits non-zero if lint, format or any test fails; every failure is reported before exiting.

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

Write-Host "== gdformat --check game/ =="
if (Get-Command gdformat -ErrorAction SilentlyContinue) {
	gdformat --check game/
	if ($LASTEXITCODE -ne 0) { $failed = $true }
} else {
	Write-Host "test.ps1: gdformat not found - install dev deps: pip install -r requirements-dev.txt"
	$failed = $true
}

Write-Host "== godot --headless --path game --import =="
& (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game --import
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "== gdUnit4 (res://tests) =="
# Zero-suite guard (P0.15, review CODE-2): gdUnit4 prints "No test cases found, abort
# test run!" and still exits 0 — a renamed or lost test root must not stay green.
$suiteScripts = Get-ChildItem -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue game/tests
if (-not (Test-Path game/tests) -or -not $suiteScripts) {
	Write-Host "test.ps1: no test scripts under game/tests/ - refusing to pass with zero tests"
	$failed = $true
} else {
	# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6 refuses
	# headless unless told (UI input events don't work headless — keep tests logic-only).
	$gdunitOut = & (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game `
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd `
		-a res://tests -c --ignoreHeadlessMode 2>&1 | Out-String
	Write-Output $gdunitOut
	if ($LASTEXITCODE -ne 0 -or $gdunitOut.Contains('No test cases found')) {
		Write-Host "test.ps1: gdUnit4 failed or discovered zero test cases"
		$failed = $true
	}
}

Write-Host "== standalone tests (game/tests/*.gd, non-gdUnit4) =="
# GdUnitTestSuite files are covered by the stage above; every other top-level
# game/tests/*.gd runs as a SceneTree --script (e.g. test_bridge.gd).
# Convention: suites extend GdUnitTestSuite directly; shared helpers go in a subdir.
foreach ($t in (Get-ChildItem -Filter *.gd -File -ErrorAction SilentlyContinue game/tests)) {
	if (Select-String -Path $t.FullName -Pattern 'extends\s+GdUnitTestSuite' -Quiet) { continue }
	Write-Host "-- $($t.Name)"
	& (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game --script "res://tests/$($t.Name)"
	if ($LASTEXITCODE -ne 0) { $failed = $true }
}

Pop-Location
if ($failed) {
	Write-Host "test.ps1: FAILED"
	exit 1
}
Write-Host "test.ps1: all checks passed"
exit 0
