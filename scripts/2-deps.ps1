<#
2-deps.ps1 — Ai, ai, ai! Bootstrap v0.1.2
Install system dependencies. Requires admin rights.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator rights required for winget installs."
    Write-Host "Right-click PowerShell and select 'Run as Administrator'."
    exit 1
}

Write-Host "Installing prerequisites..."
Write-Host ""

# ── Winget Installs ──
# Each runs winget install with --accept-source-agreements.
# Exit code 0 = installed; non-zero = already up to date or failed.
# Results are collected in $results array for summary output.
# Requires admin rights (checked above).
# ─────────────────────

$results = @()

Write-Host "--- Git ---"
$result = winget install Git.Git --accept-source-agreements 2>&1
$results += @{Name="Git"; Status=if ($LASTEXITCODE -eq 0) {"Installed"} else {"Skipped (already up to date)"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "--- Python 3.10 ---"
$result = winget install Python.Python.3.10 --accept-source-agreements 2>&1
$results += @{Name="Python 3.10"; Status=if ($LASTEXITCODE -eq 0) {"OK"} else {"FAILED or already installed"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "--- Python 3.11 ---"
$result = winget install Python.Python.3.11 --accept-source-agreements 2>&1
$results += @{Name="Python 3.11"; Status=if ($LASTEXITCODE -eq 0) {"OK"} else {"FAILED or already installed"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "--- Python 3.12 ---"
$result = winget install Python.Python.3.12 --accept-source-agreements 2>&1
$results += @{Name="Python 3.12"; Status=if ($LASTEXITCODE -eq 0) {"OK"} else {"FAILED or already installed"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "--- Ollama ---"
$result = winget install Ollama.Ollama --accept-source-agreements 2>&1
$results += @{Name="Ollama"; Status=if ($LASTEXITCODE -eq 0) {"OK"} else {"FAILED or already installed"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "--- FFmpeg ---"
$result = winget install FFmpeg --accept-source-agreements 2>&1
$results += @{Name="FFmpeg"; Status=if ($LASTEXITCODE -eq 0) {"OK"} else {"FAILED or already installed"}}
if ($LASTEXITCODE -ne 0) { Write-Host "$result" }
Write-Host ""

Write-Host "========================="
Write-Host " Ai, ai, ai! Bootstrap v0.1.2"
Write-Host "========================="
Write-Host "Install Summary"
foreach ($r in $results) { Write-Host "  $($r.Name): $($r.Status)" }
Write-Host "========================"
Write-Host ""
Write-Host "IMPORTANT: Close ALL PowerShell windows, open a new one."
Write-Host "Then verify with: py -0, git --version, ollama --version"
Write-Host "Python 3.12 needed for ROCm ComfyUI backend (optional)"
Write-Host ""
Write-Host ""

# Auto-configure environment variables to prevent misdirected storage
Write-Host "Configuring environment variables..."
Write-Host ""

# ── Environment Variables ──
# Sets OLLAMA_MODELS, HF_HOME, TORCH_HOME as User-scope environment vars.
# Redirects download caches to AI_CACHE and model storage to AI_VAULT.
# Detects root path by checking common locations for AI_CONFIG marker file.
# Only sets if architecture was initialized (1-init.ps1 run).
# Requires PowerShell restart to take effect.
# ──────────────────────────

$rootCandidates = @("D:\AI", "$env:AI_ROOT")
$detectedRoot = $null
foreach ($c in $rootCandidates) { if (Test-Path "$c\AI_CONFIG") { $detectedRoot = $c; break } }

if ($detectedRoot) {
    # OLLAMA_MODELS — redirects model storage to vault
    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "$detectedRoot\AI_VAULT\models\llm", "User")
    Write-Host "  OLLAMA_MODELS = $detectedRoot\AI_VAULT\models\llm"

    # HF_HOME — keeps huggingface cache out of vault
    [Environment]::SetEnvironmentVariable("HF_HOME", "$detectedRoot\AI_CACHE\huggingface", "User")
    Write-Host "  HF_HOME       = $detectedRoot\AI_CACHE\huggingface"

    # TORCH_HOME — keeps torch cache out of vault
    [Environment]::SetEnvironmentVariable("TORCH_HOME", "$detectedRoot\AI_CACHE\torch", "User")
    Write-Host "  TORCH_HOME    = $detectedRoot\AI_CACHE\torch"

    Write-Host ""
    Write-Host "Environment variables set. Restart PowerShell and Ollama for them to take effect."
} else {
    Write-Host "  AI architecture not detected (run 1-init.ps1 first). Env vars not set."
    Write-Host "  Run 'ai setup env' after initializing the architecture."
}

Write-Host ""
Write-Host "Next step: Restart PowerShell, then run 3-apps.ps1"
