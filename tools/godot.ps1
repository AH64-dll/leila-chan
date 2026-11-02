# Launch the pinned Godot binary (game/.godot-version).
# The binary is a local artifact (gitignored): <main worktree>/tools/godot/, see README "Local artifacts".
# Resolution: $env:LEILA_GODOT, then <repo>/tools/godot/, then <main worktree>/tools/godot/.
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$pin = (Get-Content -LiteralPath (Join-Path $repo 'game/.godot-version') -Raw).Trim()

if ($env:LEILA_GODOT) {
	if (-not (Test-Path -LiteralPath $env:LEILA_GODOT)) {
		Write-Error "godot.ps1: LEILA_GODOT not found: $env:LEILA_GODOT"
		exit 1
	}
	& $env:LEILA_GODOT @args
	exit $LASTEXITCODE
}

$bin = "Godot_v${pin}_win64.exe"
$main = $repo
if (Get-Command git -ErrorAction SilentlyContinue) {
	$firstWorktree = git -C $repo worktree list --porcelain 2>$null |
		Where-Object { $_ -like 'worktree *' } | Select-Object -First 1
	if ($firstWorktree) {
		$main = $firstWorktree.Substring(9).Trim()
	}
}

foreach ($dir in @((Join-Path $repo 'tools/godot'), (Join-Path $main 'tools/godot'))) {
	$candidate = Join-Path $dir $bin
	if (Test-Path -LiteralPath $candidate) {
		& $candidate @args
		exit $LASTEXITCODE
	}
}

Write-Error "godot.ps1: Godot $pin not found (looked in tools/godot); set LEILA_GODOT or see README 'Local artifacts'."
exit 1
