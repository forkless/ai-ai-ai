<#
install-comfyui-deps.ps1 — Extra Python dependencies for ComfyUI
Installs packages into the active ComfyUI venv (venv or venv_rocm).
Run after 3-comfyui.ps1 or ai install comfyui.
#>

# ── Root Path Detection ──
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

$comfyPath = "${Root}\AI_CORE\Apps\ComfyUI"

# ── Detect which venv is active (read backend from config) ──
$configPath = "${Root}\AI_CONFIG\system_config.json"
$venvName = "venv"
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($cfg.comfyui_backend -eq "rocm") { $venvName = "venv_rocm" }
}

$pythonExe = "${comfyPath}\${venvName}\Scripts\python.exe"
if (!(Test-Path $pythonExe)) {
    Write-Host "ERROR: Python not found at ${pythonExe}"
    Write-Host "Make sure ComfyUI is installed (run 3-comfyui.ps1 or ai install comfyui)."
    exit 1
}

Write-Host "ComfyUI path: $comfyPath"
Write-Host "Using venv:   $venvName"
Write-Host "Python:       $pythonExe"
Write-Host ""

# ── Install dependencies ──
Write-Host "=== Upgrading numpy ==="
& $pythonExe -m pip install --upgrade numpy
if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: numpy upgrade failed (non-critical)" }

Write-Host ""
Write-Host "=== Installing onnx ==="
& $pythonExe -m pip install onnx
if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: onnx install failed" }

Write-Host ""
Write-Host "=== Installing insightface (local wheel) ==="
$wheelPath = "insightface-0.7.3-cp312-cp312-win_amd64.whl"
if ($venvName -eq "venv_rocm") {
    # ROCm venv is cp312 — wheel matches
    if (Test-Path $wheelPath) {
        & $pythonExe -m pip install --force-reinstall $wheelPath
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: insightface install failed"; exit 1 }
    } else {
        Write-Host "WARNING: $wheelPath not found in current directory. Place it here or specify full path."
        Write-Host "Skipping insightface."
    }
} else {
    Write-Host "Skipping insightface (wheel is cp312, active venv is Python 3.11)"
    Write-Host "Switch to ROCm backend or download a cp311-compatible wheel."
}

Write-Host ""
Write-Host "Done."
