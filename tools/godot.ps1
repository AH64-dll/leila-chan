# Launch the pinned Godot binary (game/.godot-version).
# The binary is a local artifact (gitignored): <main worktree>/tools/godot/, see README "Local artifacts".
# Resolution: $env:LEILA_GODOT, then <repo>/tools/godot/, then <main worktree>/tools/godot/.
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$pin = (Get-Content -LiteralPath (Join-Path $repo 'game/.godot-version') -Raw).Trim()

# Windows PowerShell 5.1 promotes native stderr to an ErrorRecord; under
# ErrorActionPreference=Stop that is a terminating NativeCommandError even when
# the process exits 0. Godot writes expected WARNING: lines to stderr, so relax
# the preference for the native invocation only (P1.30): config and script
# errors above stay fail-closed, stderr still reaches the caller, and the
# process's real exit code is propagated. A process that never starts leaves
# $LASTEXITCODE null, which fails closed instead of exiting 0.
function Invoke-Godot {
	param([string]$Exe, [string[]]$Arguments)
	$previous = $ErrorActionPreference
	$global:LASTEXITCODE = $null
	$ErrorActionPreference = 'Continue'
	try {
		& $Exe @Arguments
		$code = $global:LASTEXITCODE
	} finally {
		$ErrorActionPreference = $previous
	}
	if ($null -eq $code) {
		Write-Error "godot.ps1: failed to start: $Exe"
		exit 1
	}
	exit $code
}

if ($env:LEILA_GODOT) {
	if (-not (Test-Path -LiteralPath $env:LEILA_GODOT)) {
		Write-Error "godot.ps1: LEILA_GODOT not found: $env:LEILA_GODOT"
		exit 1
	}
	Invoke-Godot $env:LEILA_GODOT $args
}

# Prefer *_console.exe (console subsystem): its stdout reaches pipes and redirects.
# The plain .exe is GUI-subsystem and writes to CONOUT$, bypassing PowerShell capture.
$bins = @("Godot_v${pin}_win64_console.exe", "Godot_v${pin}_win64.exe")
$main = $repo
if (Get-Command git -ErrorAction SilentlyContinue) {
	# Optional probe: a copy outside a git worktree makes git write to stderr,
	# which Stop would turn into a NativeCommandError before resolution even
	# starts. Its stderr is deliberately discarded and its failure is non-fatal.
	$previous = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try {
		$firstWorktree = git -C $repo worktree list --porcelain 2>$null |
			Where-Object { $_ -like 'worktree *' } | Select-Object -First 1
	} finally {
		$ErrorActionPreference = $previous
	}
	if ($firstWorktree) {
		$main = $firstWorktree.Substring(9).Trim()
	}
}

foreach ($dir in @((Join-Path $repo 'tools/godot'), (Join-Path $main 'tools/godot'))) {
	foreach ($bin in $bins) {
		$candidate = Join-Path $dir $bin
		if (Test-Path -LiteralPath $candidate) {
			Invoke-Godot $candidate $args
		}
	}
}

Write-Error "godot.ps1: Godot $pin not found (looked in tools/godot); set LEILA_GODOT or see README 'Local artifacts'."
exit 1
