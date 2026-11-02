# Run the full GDScript check suite headless (P0.06; hardened in P0.15):
#   1) gdlint over game/            (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) gdformat --check over game/  (config: repo-root gdformatrc; format drift gates too)
#   3) godot --import               (rebuilds the class cache; needed on a fresh checkout)
#   4) gdUnit4 suites res://tests   (vendored addon, via tools/godot.ps1 / $env:LEILA_GODOT;
#                                   streamed transcript in game/reports/gdunit_console.log)
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
# Zero-suite guard (P0.15, review CODE-2; reworked P0.18, review CODE-1/2):
# gdUnit4 exits 0 when it discovers zero test cases, so its exit code alone
# cannot be trusted. The check asserts on the JUnit report artifact, not on
# console text: the zero-case path quits before a session starts, so no
# results.xml is written. game/reports is wiped first so only THIS run's
# report can match. Upgrade note: if gdUnit4 changes where/whether it writes
# reports/report_*/results.xml or the <testsuites tests="N"> attribute,
# re-verify this guard - a missing or unreadable report fails red, never green.
$suiteScripts = Get-ChildItem -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue game/tests
if (-not (Test-Path game/tests) -or -not $suiteScripts) {
	Write-Host "test.ps1: no test scripts under game/tests/ - refusing to pass with zero tests"
	$failed = $true
} else {
	# The transcript streams to the console AND to game/reports/gdunit_console.log
	# via an auto-flushing StreamWriter (P0.18, review CODE-1): a hung suite no
	# longer leaves zero output - everything up to the kill is already visible.
	# (Tee-Object -FilePath is not used: in Windows PowerShell it writes UTF-16.)
	# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6
	# refuses headless unless told (UI input events don't work headless - keep
	# tests logic-only).
	if (Test-Path game/reports) { Remove-Item -Recurse -Force game/reports }
	New-Item -ItemType Directory -Force game/reports | Out-Null
	$gdunitLog = New-Object System.IO.StreamWriter((Join-Path $repo 'game/reports/gdunit_console.log'))
	$gdunitLog.AutoFlush = $true
	& (Join-Path $PSScriptRoot 'godot.ps1') --headless --path game `
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd `
		-a res://tests -c --ignoreHeadlessMode 2>&1 | ForEach-Object { $gdunitLog.WriteLine([string]$_); $_ }
	$gdunitLog.Dispose()
	$gdunitStatus = $LASTEXITCODE
	$resultsXml = Get-ChildItem -Recurse -Filter results.xml -File -ErrorAction SilentlyContinue game/reports |
		Select-Object -First 1
	$gdunitTests = 0
	if ($resultsXml) {
		try {
			$gdunitTests = [int]([xml](Get-Content -Raw $resultsXml.FullName)).testsuites.tests
		} catch {
			$gdunitTests = 0
		}
	}
	if ($gdunitStatus -ne 0 -or $gdunitTests -eq 0) {
		Write-Host "test.ps1: gdUnit4 failed or discovered zero test cases (transcript: game/reports/gdunit_console.log)"
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
