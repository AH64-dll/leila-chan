<#
.SYNOPSIS
Fetch the pinned Windows llama.cpp build (b12024) into tools/llama/llama-b12024.

.DESCRIPTION
Downloads the release zip(s) from github.com/ggml-org/llama.cpp and extracts
them into one folder (server + runtime DLLs side by side). The destination is
gitignored. CUDA needs the cudart pair; Vulkan is a single zip and is the
documented fallback if the CUDA build mismatches the driver (P0 risk).

.EXAMPLE
tools/llm/fetch_llama.ps1                 # CUDA 13.4 (default, this machine)
tools/llm/fetch_llama.ps1 -Variant cuda-12.4
tools/llm/fetch_llama.ps1 -Variant vulkan # fallback
#>
[CmdletBinding()]
param(
    [ValidateSet("cuda-13.4", "cuda-12.4", "vulkan")]
    [string]$Variant = "cuda-13.4",
    [string]$Build   = "b12024",
    [string]$Dest    = ""
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (-not $Dest) { $Dest = Join-Path $Root "tools\llama\llama-$Build" }

$Base = "https://github.com/ggml-org/llama.cpp/releases/download/$Build"
$Files = switch ($Variant) {
    "cuda-13.4" { @("llama-$Build-bin-win-cuda-13.4-x64.zip", "cudart-llama-bin-win-cuda-13.4-x64.zip") }
    "cuda-12.4" { @("llama-$Build-bin-win-cuda-12.4-x64.zip", "cudart-llama-bin-win-cuda-12.4-x64.zip") }
    "vulkan"    { @("llama-$Build-bin-win-vulkan-x64.zip") }
}

New-Item -ItemType Directory -Force $Dest | Out-Null
$Tmp = Join-Path $env:TEMP "leila-llama-dl-$Build-$Variant"
New-Item -ItemType Directory -Force $Tmp | Out-Null
try {
    foreach ($f in $Files) {
        $zip = Join-Path $Tmp $f
        Write-Host "download  $Base/$f"
        curl.exe -fL --retry 3 -o $zip "$Base/$f"
        if ($LASTEXITCODE -ne 0) { throw "download failed: $f" }
        Write-Host "extract   $f -> $Dest"
        Expand-Archive -Path $zip -DestinationPath $Dest -Force
    }
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

$env:PATH = "$Dest;$env:PATH"
& (Join-Path $Dest "llama-server.exe") --version
Write-Host "Done. Binaries in $Dest (gitignored). Start with: tools/llm/serve.ps1"
