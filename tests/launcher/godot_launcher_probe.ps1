# Regression probe for tools/godot.ps1 (P1.30).
#
# Windows PowerShell 5.1 promotes native stderr to an ErrorRecord; with
# ErrorActionPreference=Stop that is a terminating NativeCommandError even when
# the process exits 0. The launcher used to abort on any Godot WARNING. Each
# case runs the launcher with the same `2>&1 | ForEach-Object` shape as
# tools/test.ps1 and asserts that stdout and the WARNING line both survive and
# that the native exit code is preserved. Both resolution branches are covered:
# LEILA_GODOT and the pinned binary resolved under tools/godot/.
#
# The fake native binary is compiled at run time with Add-Type; no binary is
# committed. Run directly:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests/launcher/godot_launcher_probe.ps1
param(
	[string]$Launcher = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools/godot.ps1')
)

$ErrorActionPreference = 'Continue'
$caseRunner = Join-Path $PSScriptRoot 'run_case.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('p130-launcher-' + [guid]::NewGuid().ToString('N'))
$passes = 0
$failures = 0

function Invoke-Probe {
	param(
		[string]$Name,
		[string]$LauncherPath,
		[string]$UseEnvExe,
		[int]$ExpectedExit,
		[string[]]$ExpectedText,
		[switch]$ExpectTermination
	)
	$argv = @(
		'-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
		'-File', $caseRunner, '-Launcher', $LauncherPath, '-ExitCode', "$ExpectedExit"
	)
	if ($UseEnvExe) { $argv += @('-UseEnvExe', $UseEnvExe) }
	$raw = & $powershell @argv 2>&1 | ForEach-Object { [string]$_ }
	$probeExit = $LASTEXITCODE
	$text = $raw -join "`n"
	$marker = [regex]::Match($text, 'LAUNCHER_EXIT=(-?\d+)')
	$problems = @()
	if ($ExpectTermination) {
		# A missing binary is a script/config failure: the launcher writes an
		# error and terminates nonzero instead of falling through to exit 0.
		if ($probeExit -eq 0) {
			$problems += 'expected a terminating failure, but the probe exited 0'
		}
		if ($text -match 'LAUNCHER_EXIT=0') {
			$problems += 'expected a terminating failure, but the launcher exited 0'
		}
	} elseif (-not $marker.Success) {
		$problems += "launcher terminated without an exit code (probe exit $probeExit)"
	} elseif ([int]$marker.Groups[1].Value -ne $ExpectedExit) {
		$problems += "launcher exit $($marker.Groups[1].Value), expected $ExpectedExit"
	}
	foreach ($needle in $ExpectedText) {
		if (-not $text.Contains($needle)) { $problems += "missing output: $needle" }
	}
	if ($problems.Count -eq 0) {
		$script:passes++
		Write-Host "PASS  $Name"
	} else {
		$script:failures++
		Write-Host "FAIL  $Name"
		$problems | ForEach-Object { Write-Host "      $_" }
		Write-Host '      ----- output -----'
		$raw | ForEach-Object { Write-Host "      $_" }
		Write-Host '      ------------------'
	}
}

try {
	New-Item -ItemType Directory -Force -Path $work | Out-Null

	$fakeExe = Join-Path $work 'fake-godot.exe'
	$source = @'
using System;
public static class FakeGodot {
    public static int Main(string[] args) {
        Console.Out.WriteLine("p130 fake stdout");
        Console.Error.WriteLine("WARNING: p130 intentional native stderr");
        int code = 0;
        foreach (string a in args) {
            if (a.StartsWith("--exit=")) { code = int.Parse(a.Substring(7)); }
        }
        return code;
    }
}
'@
	Add-Type -TypeDefinition $source -OutputAssembly $fakeExe -OutputType ConsoleApplication -ErrorAction Stop

	# A minimal fake repo so the launcher's own resolution finds the stub under
	# tools/godot/. It is deliberately outside git: that also covers the
	# launcher's optional `git worktree` probe, whose stderr must not abort.
	$pin = '9.9.9-p130'
	$resolved = Join-Path $work 'resolved'
	New-Item -ItemType Directory -Force -Path (Join-Path $resolved 'game') | Out-Null
	New-Item -ItemType Directory -Force -Path (Join-Path $resolved 'tools/godot') | Out-Null
	$pin | Set-Content -LiteralPath (Join-Path $resolved 'game/.godot-version') -Encoding ascii
	Copy-Item -LiteralPath $Launcher -Destination (Join-Path $resolved 'tools/godot.ps1') -Force
	$resolvedExe = Join-Path $resolved "tools/godot/Godot_v${pin}_win64_console.exe"
	Copy-Item -LiteralPath $fakeExe -Destination $resolvedExe -Force

	$missing = Join-Path $work 'missing'
	New-Item -ItemType Directory -Force -Path (Join-Path $missing 'game') | Out-Null
	New-Item -ItemType Directory -Force -Path (Join-Path $missing 'tools/godot') | Out-Null
	$pin | Set-Content -LiteralPath (Join-Path $missing 'game/.godot-version') -Encoding ascii
	Copy-Item -LiteralPath $Launcher -Destination (Join-Path $missing 'tools/godot.ps1') -Force

	$warning = 'WARNING: p130 intentional native stderr'
	$stdout = 'p130 fake stdout'

	Invoke-Probe 'LEILA_GODOT warning + exit 0' $Launcher $fakeExe 0 @($warning, $stdout)
	Invoke-Probe 'LEILA_GODOT stderr + exit 7' $Launcher $fakeExe 7 @($warning, $stdout)
	Invoke-Probe 'resolved binary warning + exit 0' (Join-Path $resolved 'tools/godot.ps1') $null 0 @($warning, $stdout)
	Invoke-Probe 'resolved binary stderr + exit 7' (Join-Path $resolved 'tools/godot.ps1') $null 7 @($warning, $stdout)
	Invoke-Probe 'missing resolved binary fails closed' (Join-Path $missing 'tools/godot.ps1') $null 1 @('not found (looked in tools/godot)') -ExpectTermination
	Invoke-Probe 'missing LEILA_GODOT fails closed' $Launcher (Join-Path $work 'absent.exe') 1 @('LEILA_GODOT not found') -ExpectTermination
} finally {
	Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
	Write-Host "PROBE: FAILED ($passes passed, $failures failed)"
	exit 1
}
Write-Host "PROBE: OK ($passes cases)"
exit 0
