<#
.SYNOPSIS
Start llama-server (pinned llama.cpp b12024) for Leila-chan prototype work.

.DESCRIPTION
Launches llama-server with --jinja (Qwen chat template), full GPU offload
(-ngl 99), one request slot (-np 1) - the same shape the M0 experiments used
(experiments/steer_sweep.py). An optional control vector is applied at launch;
changing the dose means restarting the server (docs/06 section 4).

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
    [double]$VectorScale = 1
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
    $LlamaArgs += @("--control-vector-scaled", "$($Vector):$($VectorScale)")
}

# Backend DLLs (ggml-cuda, cudart) are loaded dynamically by name -> bin dir on PATH.
$env:PATH = "$Bin;$env:PATH"

Write-Host "llama-server b12024"
Write-Host "  bin:    $Exe"
Write-Host "  model:  $Model"
Write-Host "  args:   $($LlamaArgs -join ' ')"
Write-Host "  health: http://127.0.0.1:$Port/health"
& $Exe @LlamaArgs
