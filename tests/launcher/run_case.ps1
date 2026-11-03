# Run one tools/godot.ps1 case in a fresh Windows PowerShell process (P1.30).
# The probe driver asserts the launcher's exit code and output. This helper
# exits 0 once it could observe them, so a launcher regression is reported as a
# probe finding; if the launcher terminates, no LAUNCHER_EXIT marker is printed
# and the driver treats that as a failure.
param(
	[Parameter(Mandatory = $true)][string]$Launcher,
	[string]$UseEnvExe,
	[int]$ExitCode = 0
)

if ($UseEnvExe) {
	$env:LEILA_GODOT = $UseEnvExe
} else {
	Remove-Item Env:LEILA_GODOT -ErrorAction SilentlyContinue
}

$output = & $Launcher "--exit=$ExitCode" 2>&1 | ForEach-Object { [string]$_ }
$native = $LASTEXITCODE
$output | ForEach-Object { "OUT: $_" }
"LAUNCHER_EXIT=$native"
exit 0
