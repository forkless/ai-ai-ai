<#
1-init.ps1 — Ai, ai, ai! Bootstrap v0.1.1
Creates folder structure + config + bindings only.
No software installation.
#>

$RootMode = Read-Host "Install path (press Enter for D:\AI)"

if ([string]::IsNullOrWhiteSpace($RootMode)) {
    $BasePath = "D:\AI"
} else {
    $BasePath = $RootMode.TrimEnd("\")
}

Write-Host "AI Root: $BasePath"

# -------------------------
# CHECK ADMIN / DEVELOPER MODE
# -------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$devMode = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense

if (-not $isAdmin -and -not $devMode) {
    Write-Host "WARNING: Symbolic links require either:"
    Write-Host "  1. Run PowerShell as Administrator"
    Write-Host "  2. Enable Developer Mode (Settings > Privacy & Security > For Developers)"
    $choice = Read-Host "Continue anyway? (y/N)"
    if ($choice -ne "y") {
        Write-Host "Aborted."
        exit 1
    }
}

# -------------------------
# FOLDERS
# -------------------------

$folders = @(
    "$BasePath",
    "$BasePath\AI_CONFIG",
    "$BasePath\AI_CORE",
    "$BasePath\AI_CORE\Apps",
    "$BasePath\AI_CORE\Services",
    "$BasePath\AI_CORE\Environments",
    "$BasePath\AI_CORE\_bindings",
    "$BasePath\AI_VAULT",
    "$BasePath\AI_VAULT\models",
    "$BasePath\AI_VAULT\models\llm",
    "$BasePath\AI_VAULT\models\diffusion",
    "$BasePath\AI_VAULT\models\diffusion\checkpoints",
    "$BasePath\AI_VAULT\models\diffusion\diffusion_models",
    "$BasePath\AI_VAULT\models\diffusion\loras",
    "$BasePath\AI_VAULT\models\diffusion\vae",
    "$BasePath\AI_VAULT\models\diffusion\controlnet",
    "$BasePath\AI_VAULT\models\diffusion\unet",
    "$BasePath\AI_VAULT\models\diffusion\text_encoders",
    "$BasePath\AI_VAULT\models\diffusion\upscale_models",
    "$BasePath\AI_VAULT\models\diffusion\ipadapter",
    "$BasePath\AI_VAULT\models\diffusion\style_models",
    "$BasePath\AI_VAULT\models\diffusion\clip_vision",
    "$BasePath\AI_VAULT\models\diffusion\clip",
    "$BasePath\AI_VAULT\models\embeddings",
    "$BasePath\AI_VAULT\datasets",
    "$BasePath\AI_WORKSPACE",
    "$BasePath\AI_WORKSPACE\workflows",
    "$BasePath\AI_WORKSPACE\input",
    "$BasePath\AI_WORKSPACE\output",
    "$BasePath\AI_WORKSPACE\sessions",
    "$BasePath\AI_TOOLS",
    "$BasePath\AI_TOOLS\scripts",
    "$BasePath\AI_TOOLS\utilities",
    "$BasePath\AI_TOOLS\converters",
    "$BasePath\AI_CACHE",
    "$BasePath\AI_CACHE\huggingface",
    "$BasePath\AI_CACHE\torch",
    "$BasePath\AI_CACHE\comfyui_temp"
)

$created = 0
$skipped = 0

foreach ($f in $folders) {
    if (!(Test-Path $f)) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
        $created++
    } else {
        $skipped++
    }
}

Write-Host "Folders: $created created, $skipped already exist"

# -------------------------
# GPU DETECTION — Queries WMI for NVIDIA/AMD. Result goes to system_config.json.
# Only affects backend choice (CUDA vs DirectML) in 3-apps.ps1.
# -------------------------

$gpuType = "unknown"
$nvidia = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
if ($nvidia) { $gpuType = "nvidia" }
$amd = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "AMD|Radeon" }
if ($amd) { $gpuType = "amd" }
Write-Host "Detected GPU: $gpuType"

# -------------------------
# SYMLINKS / BINDINGS — Creates directory junctions from AI_CORE\_bindings
# to AI_VAULT\models\ subfolders. Lets runtimes access models through a
# stable path regardless of vault layout. Requires admin or Developer Mode.
# -------------------------

$links = @(
    @{Name="llm"; Target="$BasePath\AI_VAULT\models\llm"},
    @{Name="diffusion"; Target="$BasePath\AI_VAULT\models\diffusion"},
    @{Name="embeddings"; Target="$BasePath\AI_VAULT\models\embeddings"}
)

foreach ($link in $links) {
    $linkPath = "$BasePath\AI_CORE\_bindings\$($link.Name)"
    if (!(Test-Path $linkPath)) {
        $result = cmd /c mklink /D "$linkPath" "$($link.Target)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Symlink created: $($link.Name)"
        } else {
            Write-Host "WARNING: Failed to create symlink for $($link.Name) — $result"
        }
    } else {
        Write-Host "Symlink exists: $($link.Name)"
    }
}

# -------------------------
# CONFIG FILES — Writes system_config.json (arch version, root, GPU), model_registry.json
# (empty placeholder), and ports.json (default service ports + listen address).
# Config and registry have Test-Path guards; ports.json overwrites every run.
# -------------------------

$configPath = "$BasePath\AI_CONFIG\system_config.json"
if (!(Test-Path $configPath)) {
    $config = @{
        architecture_version = "0.1.1"
        platform = "windows"
        root = $BasePath
        vault = "$BasePath\AI_VAULT"
        workspace = "$BasePath\AI_WORKSPACE"
        cache = "$BasePath\AI_CACHE"
        gpu = $gpuType
    }
    $config | ConvertTo-Json -Depth 10 | Out-File $configPath
    Write-Host "Config created: system_config.json"
} else {
    Write-Host "Config exists: system_config.json (skipped)"
}

$registryPath = "$BasePath\AI_CONFIG\model_registry.json"
if (!(Test-Path $registryPath)) {
    $modelRegistry = @{ models = @() }
    $modelRegistry | ConvertTo-Json -Depth 10 | Out-File $registryPath
    Write-Host "Config created: model_registry.json"
} else {
    Write-Host "Config exists: model_registry.json (skipped)"
}

# -------------------------
# SUMMARY
# -------------------------

# PORTS CONFIG
$portConfig = @{ollama=11434; comfyui=8188; openwebui=3000; listen="0.0.0.0"}
$portConfig | ConvertTo-Json | Out-File "${BasePath}\AI_CONFIG\ports.json" -Encoding utf8
Write-Host "Port config: ports.json (defaults)"

Write-Host ""
Write-Host "===== Ai, ai, ai! Bootstrap v0.1.1 ====="
Write-Host "Architecture initialization complete"
Write-Host "  Root: $BasePath"
Write-Host "  Folders: $created new, $skipped existing"
Write-Host "  GPU: $gpuType"
Write-Host ""
Write-Host "Next step: Restart PowerShell, then run 2-deps.ps1"
