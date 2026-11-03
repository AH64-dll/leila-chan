<#
.SYNOPSIS
Start llama-server (pinned llama.cpp b12024) for Leila-chan prototype work.

.DESCRIPTION
Launches llama-server with --jinja (Qwen chat template), full GPU offload
(-ngl 99), one request slot (-np 1) - the same shape the M0 experiments used
(experiments/steer_sweep.py). An optional control vector is applied at launch;
changing the dose means restarting the server (docs/06 section 4).

-Vector paths: llama.cpp parses --control-vector-scaled as FNAME:SCALE and
splits on ':' and ',', so a FNAME containing ':' can never reach it - on
Windows that means 'X:\...' absolute paths and the ambiguous 'X:file' form.
Both launchers normalize through tools/llm/cvec_path.py: a drive-rooted path
becomes a relative path against the server working directory (same drive
required), and 'X:file' or any name containing ':'/',' is rejected with an
explanation. Accepted: relative paths, UNC paths, 'X:\...' on the cwd's drive.
Needs python/py on PATH when -Vector is used (same as smoke.py already does).

Paths default to the repo layout and can be overridden with the LEILA_MODEL /
LEILA_LLAMA_BIN env vars or the -Model / -Bin parameters.

.EXAMPLE
tools/llm/serve.ps1

.EXAMPLE
tools/llm/serve.ps1 -Vector experiments/steering/evil_qwen_unit.gguf -VectorScale 4
#>
[CmdletBinding()]
param(
    [string]$Model       = $env:LEILA_MODEL,
    [string]$Bin         = $env:LEILA_LLAMA_BIN,
    [int]$Port           = 8089,
    [int]$CtxSize        = 8192,
    [int]$GpuLayers      = 99,
    [string]$Vector      = "",
    [double]$VectorScale = 1,
    # Print the resolved command line and exit without starting the server.
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (-not $Model) { $Model = Join-Path $Root "models\Qwen3.5-4B-Q4_K_M.gguf" }
if (-not $Bin)   { $Bin   = Join-Path $Root "tools\llama\llama-b12024" }

$Exe = Join-Path $Bin "llama-server.exe"
if (-not (Test-Path $Exe))   { throw "llama-server.exe not found at $Exe - run tools/llm/fetch_llama.ps1 (see tools/llm/README.md)" }
if (-not (Test-Path $Model)) { throw "model not found at $Model - see tools/llm/README.md" }

$LlamaArgs = @("-m", "$Model", "-ngl", "$GpuLayers", "-c", "$CtxSize",
               "--jinja", "--port", "$Port", "-np", "1")
if ($Vector) {
    if (-not (Test-Path $Vector)) { throw "control vector not found: $Vector" }
    # Normalize CVEC for the FNAME:SCALE parser via tools/llm/cvec_path.py
    # (see header): drive paths become same-drive relative paths against the
    # server cwd. The helper prints NORMALIZED then the full FLAG argument.
    $CvecPy = Join-Path $PSScriptRoot "cvec_path.py"
    $Py = $null
    foreach ($c in @("python", "py", "python3")) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { $Py = $c; break }
    }
    if (-not $Py) { throw "-Vector needs python (or py) on PATH for cvec_path.py normalization" }
    $ScaleStr = $VectorScale.ToString([Globalization.CultureInfo]::InvariantCulture)
    $PyArgs = @($CvecPy, "--platform", "windows", "--cwd", $PWD.Path,
                "--scale", $ScaleStr, "--", (Resolve-Path $Vector).Path)
    $Out = if ($Py -eq "py") { & py -3 @PyArgs } else { & $Py @PyArgs }
    if ($LASTEXITCODE -ne 0) { throw "control vector rejected: $Vector" }
    $LlamaArgs += @("--control-vector-scaled", ($Out | Select-Object -Last 1))
}

# Backend DLLs (ggml-cuda, cudart) are loaded dynamically by name -> bin dir on PATH.
$env:PATH = "$Bin;$env:PATH"

# --version prints to stderr; native stderr throws under ErrorActionPreference=Stop.
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { $Ver = & $Exe --version 2>&1 | Select-Object -First 1 } finally { $ErrorActionPreference = $eap }
if (-not $Ver) { $Ver = "(version unknown)" }
Write-Host "llama-server $Ver"
Write-Host "  bin:    $Exe"
Write-Host "  model:  $Model"
Write-Host "  args:   $($LlamaArgs -join ' ')"
Write-Host "  health: http://127.0.0.1:$Port/health"
if ($DryRun) { Write-Host "  (dry-run: not starting)"; return }
& $Exe @LlamaArgs
