<#
3-comfyui.ps1 — Ai, ai, ai! Bootstrap v1.1
Install ComfyUI and connect to AI_VAULT.
Requires: 1-init.ps1 and 2-deps.ps1 already run.
#>

# Try to read root from config first, fall back to prompt
$Root = $null
$configPaths = @("D:\AI\AI_CONFIG\system_config.json", "$env:AI_ROOT\AI_CONFIG\system_config.json")
foreach ($p in $configPaths) {
    if (Test-Path $p) {
        $cfg = Get-Content $p | ConvertFrom-Json
        $Root = $cfg.root
        break
    }
}
if (-not $Root) {
    $Root = Read-Host "Enter AI root path (e.g. D:\AI)"
}
$Root = $Root.TrimEnd("\")

# Guard: verify critical environment variables
Write-Host "Checking environment variables..."
$envChecks = @(
    @{Var="OLLAMA_MODELS"; Expect="${Root}\AI_VAULT\models\llm"; Desc="Ollama model storage"}
)
$envOk = $true
foreach ($check in $envChecks) {
    $val = [Environment]::GetEnvironmentVariable($check.Var, "User")
    if ($val -ne $check.Expect) {
        Write-Host "  [MIS] $($check.Var) — $($check.Desc)"
        Write-Host "        Expected: $($check.Expect)"
        Write-Host "        Current:  $(if ($val) {$val} else {'(not set)'})"
        Write-Host "        Run 'ai setup env' to fix, then restart PowerShell and try again."
        $envOk = $false
    } else {
        Write-Host "  [OK]  $($check.Var)"
    }
}
if (-not $envOk) {
    Write-Host ""
    Write-Host "Environment check failed. Fix with 'ai setup env', restart PowerShell, then re-run this script."
    exit 1
}
Write-Host ""

$ComfyPath = "${Root}\AI_CORE\Apps\ComfyUI"

# Execution policy check
$policy = Get-ExecutionPolicy
if ($policy -eq "Restricted") {
    Write-Host "PowerShell execution policy is Restricted — venv activation will fail."
    $choice = Read-Host "Set to RemoteSigned for current user? (Y/n)"
    if ($choice -ne "n") {
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        Write-Host "Execution policy set to RemoteSigned"
    } else {
        Write-Host "WARNING: venv activation may fail."
    }
}

# Clone
if (!(Test-Path $ComfyPath)) {
    Write-Host "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$ComfyPath"
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Git clone failed."; exit 1 }
} else {
    Write-Host "ComfyUI folder exists — skipping clone"
}

Set-Location "$ComfyPath"

# Venv — create if missing or missing DirectML module (AMD)
$recreateVenv = $false
if ((Test-Path ".\venv") -and $gpuType -eq "amd") {
    # Check if DirectML backend is installed
    $dmlCheck = & ".\venv\Scripts\python.exe" -c "import torch_directml; print('ok')" 2>$null
    if ($dmlCheck -ne "ok") {
        Write-Host "AMD GPU — DirectML backend not found, recreating venv"
        $recreateVenv = $true
    }
}
if ($recreateVenv -or !(Test-Path ".\venv")) {
    if ($recreateVenv) { Remove-Item -Recurse -Force ".\venv" }
    Write-Host "Creating Python 3.11 environment..."
    $venvResult = py -3.11 -m venv venv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create venv — $venvResult"
        Write-Host "Make sure Python 3.11 is installed and terminal was restarted."
        exit 1
    }
} else {
    Write-Host "Python environment exists — updating..."
}

# GPU detection
$gpu = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
$gpuType = if ($gpu) { "nvidia" } else { "amd" }
Write-Host "Detected GPU: $gpuType"

# Install deps
Write-Host "Installing requirements..."
try {
    .\venv\Scripts\Activate.ps1

    if ($gpuType -eq "amd") {
        # Install DirectML stack (replaces CUDA torch with CPU torch)
        Write-Host "AMD GPU — installing DirectML stack..."
        pip install torch-directml 2>&1 | Out-Null
        # Install full requirements (includes CUDA torchaudio — will be fixed next)
        pip install -r requirements.txt 2>&1 | Out-Null
        # Reinstall torchaudio from CPU index, then nuke stale CUDA DLLs
        Write-Host "  Replacing CUDA torchaudio with CPU version..."
        pip install torchaudio --force-reinstall --no-deps --no-cache-dir --index-url https://download.pytorch.org/whl/cpu 2>&1 | Out-Null
        # Stub out the extension module (CUDA DLLs cause hard crashes on AMD)
        $extDir = "${ComfyPath}\venv\Lib\site-packages\torchaudio\_extension"
        if (Test-Path $extDir) { Remove-Item -Recurse -Force $extDir }
        New-Item -Path "${ComfyPath}\venv\Lib\site-packages\torchaudio\_extension" -ItemType Directory -Force | Out-Null
        @"
_IS_TORCHAUDIO_EXT_AVAILABLE = False
def fail_if_no_align(f): return f
def _init_extension(): pass
def _load_lib(*a): return False
"@ | Set-Content -Path "${ComfyPath}\venv\Lib\site-packages\torchaudio\_extension\__init__.py"
        Write-Host "  DirectML and CPU torchaudio ready"
    } else {
        pip install -r requirements.txt 2>&1 | Out-Null
    }
} catch {
    Write-Host "ERROR: pip install failed — $_"
    exit 1
}

# Extra model paths
Write-Host "Configuring model paths..."
$yaml = @"
vault_config:
    checkpoints: ${Root}\AI_VAULT\models\diffusion\checkpoints
    loras: ${Root}\AI_VAULT\models\diffusion\loras
    vae: ${Root}\AI_VAULT\models\diffusion\vae
    controlnet: ${Root}\AI_VAULT\models\diffusion\controlnet
    unet: ${Root}\AI_VAULT\models\diffusion\unet
    text_encoders: ${Root}\AI_VAULT\models\diffusion\text_encoders
    upscale_models: ${Root}\AI_VAULT\models\diffusion\upscale_models
    ipadapter: ${Root}\AI_VAULT\models\diffusion\ipadapter
    style_models: ${Root}\AI_VAULT\models\diffusion\style_models
    clip_vision: ${Root}\AI_VAULT\models\diffusion\clip_vision
    embeddings: ${Root}\AI_VAULT\models\embeddings
"@
$yaml | Out-File "${ComfyPath}\extra_model_paths.yaml" -Encoding utf8

# Quick validation
Write-Host "Validating extra_model_paths.yaml..."
$yamlLines = Get-Content "${ComfyPath}\extra_model_paths.yaml"
$firstLine = $yamlLines[0].Trim()
if ($firstLine -match "^[a-zA-Z_]+:$" -and $yamlLines.Count -gt 1 -and $yamlLines[1] -match "^\s+[a-zA-Z_]+:") {
    Write-Host "  OK: named config block detected"
} else {
    Write-Host "  WARNING: format may be wrong — dumping file:"
    $yamlLines | ForEach-Object { Write-Host "    >$_<" }
    Write-Host "  First line trimmed: '${firstLine}'"
}

# Launcher with GPU flag and port config
Write-Host "Creating launcher..."
$gpuFlag = if ($gpuType -eq "amd") { " --directml" } else { "" }
$portFile = "${Root}\AI_CONFIG\ports.json"
$comfyPort = 8188
$listenAddr = "0.0.0.0"
if (Test-Path $portFile) {
    $cfg = Get-Content $portFile -Raw | ConvertFrom-Json
    if ($cfg.comfyui -and $cfg.comfyui -gt 0) { $comfyPort = [int]$cfg.comfyui }
    if ($cfg.listen) { $listenAddr = $cfg.listen }
}
$launcher = @"
Set-Location "$ComfyPath"
.\venv\Scripts\Activate.ps1
python main.py --listen $listenAddr --port $comfyPort --temp-directory "${Root}\AI_CACHE\comfyui_temp"$gpuFlag
"@
$toolsDir = "${Root}\AI_TOOLS"
if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
$launcher | Out-File "${Root}\AI_TOOLS\launch_comfyui.ps1" -Encoding utf8

# Summary
Write-Host ""
Write-Host "========================="
Write-Host " Ai, ai, ai! Bootstrap v1.1"
Write-Host "========================="
Write-Host "ComfyUI installed"
Write-Host "  Location: $ComfyPath"
Write-Host "  Venv: ${ComfyPath}\venv (Python 3.11)"
Write-Host "  Model paths: extra_model_paths.yaml"
Write-Host "  Launcher: ${Root}\AI_TOOLS\launch_comfyui.ps1"
Write-Host "  Temp dir: ${Root}\AI_CACHE\comfyui_temp"
Write-Host "  GPU: $gpuType"
Write-Host "========================"
Write-Host ""
Write-Host "Daily launch: ${Root}\AI_TOOLS\launch_comfyui.ps1"
Write-Host "Re-run 3-comfyui.ps1 to update ComfyUI and dependencies (safe, doesn't destroy venv)"
