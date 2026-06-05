<#
3-comfyui.ps1 — Ai, ai, ai! Bootstrap v1.1.2
Install ComfyUI and connect to AI_VAULT.
Requires: 1-init.ps1 and 2-deps.ps1 already run.
Parameter: -Backend directml|rocm (AMD only, defaults to prompt)
#>
param(
    [ValidateSet("directml", "rocm")]
    [string]$Backend = ""
)

# ── Root Path Detection ──
# Tries system_config.json first, then falls back to user prompt.
# Reads root path from JSON, not from environment variables directly.
# ─────────────────────────

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
# ── Environment Variable Verification ──
# Confirms OLLAMA_MODELS points to vault before proceeding.
# Prevents ComfyUI from pulling models to the wrong location.
# Exits with code 1 if variable is wrong; run 'ai setup env' to fix.
# ──────────────────────────────────────

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

# GPU detection
$gpu = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
$gpuType = if ($gpu) { "nvidia" } else { "amd" }
Write-Host "Detected GPU: $gpuType"

# Backend selection for AMD
if ($gpuType -eq "amd" -and [string]::IsNullOrEmpty($Backend)) {
    Write-Host "Choose ComfyUI backend for AMD GPU:"
    Write-Host "  1) directml — DirectML (compatible, slower, Python 3.11)"
    Write-Host "  2) rocm    — ROCm (native, faster, Python 3.12, needs AMD driver 26.2.2+)"
    $choice = Read-Host "Select backend (default: directml)"
    $Backend = if ($choice -eq "2") { "rocm" } else { "directml" }
}
if ($gpuType -eq "amd" -and [string]::IsNullOrEmpty($Backend)) { $Backend = "directml" }

$venvName = if ($Backend -eq "rocm") { "venv_rocm" } else { "venv" }
$pythonVer = if ($Backend -eq "rocm") { "3.12" } else { "3.11" }

# Venv creation
if ($gpuType -eq "nvidia") {
    # NVIDIA — single venv, no backend choice
    if (!(Test-Path ".\venv")) {
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
} else {
    # AMD — backend-specific venv
    if ($Backend -eq "rocm" -and !(Test-Path ".\venv_rocm")) {
        Write-Host "Creating Python $pythonVer environment ($venvName)..."
        $venvResult = py -3.12 -m venv venv_rocm 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to create venv — $venvResult"
            Write-Host "Make sure Python 3.12 is installed (run 2-deps.ps1) and terminal was restarted."
            exit 1
        }
    } elseif ($Backend -eq "directml") {
        $recreateVenv = $false
        if (Test-Path ".\venv") {
            $dmlCheck = & ".\venv\Scripts\python.exe" -c "import torch_directml; print('ok')" 2>$null
            if ($dmlCheck -ne "ok") {
                Write-Host "AMD GPU — DirectML backend not found, recreating venv"
                $recreateVenv = $true
            }
        }
        if ($recreateVenv -or !(Test-Path ".\venv")) {
            if ($recreateVenv) { Remove-Item -Recurse -Force ".\venv" }
            Write-Host "Creating Python $pythonVer environment..."
            $venvResult = py -3.11 -m venv venv 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: Failed to create venv — $venvResult"
                Write-Host "Make sure Python 3.11 is installed and terminal was restarted."
                exit 1
            }
        } else {
            Write-Host "Python environment exists — updating..."
        }
    }
}

# ── pip Install ──
Write-Host "Installing requirements..."

try {
    if ($gpuType -eq "nvidia") {
        .\venv\Scripts\Activate.ps1
        pip install -r requirements.txt 2>&1 | Out-Null
        deactivate
    } elseif ($Backend -eq "rocm") {
        .\venv_rocm\Scripts\Activate.ps1
        Write-Host "AMD GPU — installing ROCm stack (PyTorch $pythonVer)..."
        # ROCm SDK core + PyTorch from AMD repo
        pip install --no-cache-dir `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_core-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm-7.2.1.tar.gz 2>&1 | Out-Null
        pip install --no-cache-dir `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl 2>&1 | Out-Null
        # Install remaining ComfyUI deps
        pip install -r requirements.txt 2>&1 | Out-Null
        Write-Host "  ROCm stack installed (torch 2.9.1 + ROCm 7.2.1)"
        deactivate
    } else {
        .\venv\Scripts\Activate.ps1
        Write-Host "AMD GPU — installing DirectML stack..."
        pip install torch-directml 2>&1 | Out-Null
        pip install -r requirements.txt 2>&1 | Out-Null
        Write-Host "  Replacing CUDA torchaudio with CPU version..."
        pip install torchaudio --force-reinstall --no-deps --no-cache-dir --index-url https://download.pytorch.org/whl/cpu 2>&1 | Out-Null
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
        deactivate
    }
} catch {
    Write-Host "ERROR: pip install failed — $_"
    exit 1
}

# Write backend to system_config.json for Manage-ComfyUI to read
$configPath = "${Root}\AI_CONFIG\system_config.json"
$cfg = $null
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
}
if (-not $cfg) { $cfg = New-Object PSObject }
if ($gpuType -eq "amd") {
    $cfg | Add-Member -MemberType NoteProperty -Name "comfyui_backend" -Value $Backend -Force
    $cfg | ConvertTo-Json -Depth 10 | Out-File $configPath -Encoding utf8
    Write-Host "system_config.json updated: comfyui_backend=$Backend"
}

# Extra model paths
Write-Host "Configuring model paths..."

# Ensure vault directories exist
$vaultDirs = @(
    "${Root}\AI_VAULT\models\diffusion\checkpoints",
    "${Root}\AI_VAULT\models\diffusion\diffusion_models",
    "${Root}\AI_VAULT\models\diffusion\loras",
    "${Root}\AI_VAULT\models\diffusion\vae",
    "${Root}\AI_VAULT\models\diffusion\controlnet",
    "${Root}\AI_VAULT\models\diffusion\unet",
    "${Root}\AI_VAULT\models\diffusion\text_encoders",
    "${Root}\AI_VAULT\models\diffusion\upscale_models",
    "${Root}\AI_VAULT\models\diffusion\ipadapter",
    "${Root}\AI_VAULT\models\diffusion\style_models",
    "${Root}\AI_VAULT\models\diffusion\clip_vision",
    "${Root}\AI_VAULT\models\diffusion\clip",
    "${Root}\AI_VAULT\models\embeddings",
    "${Root}\AI_VAULT\models\insightface",
    "${Root}\AI_VAULT\models\ultralytics",
    "${Root}\AI_VAULT\models\ultralytics\bbox"
)
foreach ($d in $vaultDirs) {
    if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$yaml = @"
vault_config:
    checkpoints: ${Root}\AI_VAULT\models\diffusion\checkpoints
    diffusion_models: ${Root}\AI_VAULT\models\diffusion\diffusion_models
    loras: ${Root}\AI_VAULT\models\diffusion\loras
    vae: ${Root}\AI_VAULT\models\diffusion\vae
    controlnet: ${Root}\AI_VAULT\models\diffusion\controlnet
    unet: ${Root}\AI_VAULT\models\diffusion\unet
    text_encoders: ${Root}\AI_VAULT\models\diffusion\text_encoders
    upscale_models: ${Root}\AI_VAULT\models\diffusion\upscale_models
    ipadapter: ${Root}\AI_VAULT\models\diffusion\ipadapter
    style_models: ${Root}\AI_VAULT\models\diffusion\style_models
    clip_vision: ${Root}\AI_VAULT\models\diffusion\clip_vision
    clip: ${Root}\AI_VAULT\models\diffusion\clip
    embeddings: ${Root}\AI_VAULT\models\embeddings
    insightface: ${Root}\AI_VAULT\models\insightface
    ultralytics_bbox: ${Root}\AI_VAULT\models\ultralytics\bbox
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
$activatePath = if ($gpuType -eq "amd" -and $Backend -eq "rocm") { ".\venv_rocm\Scripts\Activate.ps1" } else { ".\venv\Scripts\Activate.ps1" }
$gpuFlag = if ($gpuType -eq "amd" -and $Backend -ne "rocm") { " --directml" } else { "" }
$portFile = "${Root}\AI_CONFIG\ports.json"
$comfyPort = 8188
$listenAddr = "0.0.0.0"
if (Test-Path $portFile) {
    $cfg = Get-Content $portFile -Raw | ConvertFrom-Json
    if ($cfg.comfyui -and $cfg.comfyui -gt 0) { $comfyPort = [int]$cfg.comfyui }
    if ($cfg.listen) { $listenAddr = $cfg.listen }
}
$logDir = "${Root}\AI_CACHE\logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$launcher = @"
`$logFile = "$logDir\comfyui.log"
Set-Location "$ComfyPath"
$activatePath
python main.py --listen $listenAddr --port $comfyPort --temp-directory "${Root}\AI_CACHE\comfyui_temp"$gpuFlag *>> "`$logFile"
"@
$toolsDir = "${Root}\AI_TOOLS"
if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
$launcher | Out-File "${Root}\AI_TOOLS\launch_comfyui.ps1" -Encoding utf8

# Summary
Write-Host ""
Write-Host "========================="
Write-Host " Ai, ai, ai! Bootstrap v1.1.2"
Write-Host "========================="
Write-Host "ComfyUI installed"
Write-Host "  Location: $ComfyPath"
$displayVenv = if ($gpuType -eq "amd" -and $Backend -eq "rocm") { "${ComfyPath}\venv_rocm (Python 3.12, ROCm)" } elseif ($gpuType -eq "amd") { "${ComfyPath}\venv (Python 3.11, DirectML)" } else { "${ComfyPath}\venv (Python 3.11, CUDA)" }
Write-Host "  Venv: $displayVenv"
Write-Host "  Model paths: extra_model_paths.yaml"
Write-Host "  Launcher: ${Root}\AI_TOOLS\launch_comfyui.ps1"
Write-Host "  Temp dir: ${Root}\AI_CACHE\comfyui_temp"
Write-Host "  GPU: $gpuType"
Write-Host "========================"
Write-Host ""
Write-Host "Daily launch: ${Root}\AI_TOOLS\launch_comfyui.ps1"
Write-Host "Re-run 3-comfyui.ps1 to update ComfyUI and dependencies (safe, doesn't destroy venv)"
