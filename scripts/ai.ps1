<#
Ai, ai, ai! Control Panel v0.1.2 — daily driver for the Ai Bootstrap system
Usage:  ai <command> [options]

Commands:
  install <app>      Install an AI application (comfyui, comfyui-manager, ollama, openwebui)
  start <service>    Start a service (all, ollama, comfyui, openwebui)
  stop <service>     Stop a service (all, ollama, comfyui, openwebui)
  restart <service>  Restart a service (all, ollama, comfyui, openwebui)
  status [service]   System health or specific service status
  doctor             Full system diagnostics
  list               List installed models, checkpoints, embeddings
  clean cache        Clear temporary files
  setup env          Check and fix environment variables
  setup path         Add AI_TOOLS to PATH for 'ai' from anywhere
  setup ports        Configure service ports
  help               Show this message
#>

# Detect root — try config first, then common paths, then prompt
$Root = $null
$configCandidates = @("D:\AI\AI_CONFIG\system_config.json", "$env:AI_ROOT\AI_CONFIG\system_config.json")
foreach ($p in $configCandidates) {
    if (Test-Path $p) {
        try { $cfg = Get-Content $p | ConvertFrom-Json; $Root = $cfg.root; break } catch {}
    }
}
if (-not $Root -and (Test-Path "D:\AI")) { $Root = "D:\AI" }
if (-not $Root -and $env:AI_ROOT) { $Root = $env:AI_ROOT }

if (-not $Root) {
    $input = Read-Host "AI root not found. Enter path (e.g. D:\AI)"
    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Host "Aborted."
        exit 1
    }
    $Root = $input.TrimEnd("\")
}

if (!(Test-Path $Root)) {
    Write-Host "WARNING: $Root does not exist yet. Run 1-init.ps1 first, then try again."
}

$Command = $args[0]
$SubCommand = $args[1]

# Normalize --version to version
if ($Command -eq "--version" -or $Command -eq "-v") { $Command = "version" }

# Easter egg
if ($Command -eq "--boobs") { Write-Host "(o)(o)`n"; Write-Host "The fastest stable diffussion of boobs... ever."; exit 0 }

# Extract -Backend option from remaining args
$BackendArg = ""
for ($i = 2; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Backend" -and $i + 1 -lt $args.Count) { $BackendArg = $args[$i + 1] }
}

<#
.SYNOPSIS Displays the full command reference in a bordered box.
No side effects. Uses $cmd format string for column alignment.
#>
function Show-Help {
    $cmd = "  {0,-26}{1}"
    $boxWidth = 78
    $title = " Ai, ai, ai! Control Panel v0.1.2 "
    $inner = $boxWidth - 2
    $lPad = [Math]::Max(0, [Math]::Floor(($inner - $title.Length) / 2))
    Write-Host "┌$("─" * $inner)┐"
    Write-Host ("│" + " " * $lPad + $title + " " * ($inner - $lPad - $title.Length) + "│")
    Write-Host "└$("─" * $inner)┘"
    Write-Host ""
    Write-Host "Usage: ai <command>"
    Write-Host ""
    Write-Host ($cmd -f "install <service>",       "Install or update comfyui, comfyui-manager, ollama, openwebui or all")
    Write-Host ($cmd -f "start <service>",        "Start a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "stop <service>",         "Stop a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "restart <service>",       "Restart a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "status <service>",       "System health or specific service status")
    Write-Host ($cmd -f "doctor",                 "Full system diagnostics (Git, Python, services, env)")
    Write-Host ($cmd -f "list",                   "List installed models, checkpoints, embeddings")
    Write-Host ($cmd -f "clean cache",            "Free up disk space — pin models to keep to AI_VAULT first")
    Write-Host ($cmd -f "setup env",              "Check and fix environment variables")
    Write-Host ($cmd -f "setup path",             "Add AI_TOOLS to your PATH so 'ai' works from any path")
    Write-Host ($cmd -f "setup ports",            "Configure service ports")
    Write-Host ($cmd -f "watch <service>",        "Watch service log (comfyui, ollama, openwebui)")
    Write-Host ($cmd -f "version",                "Show version info")
    Write-Host ($cmd -f "help",                   "Show this message")
    Write-Host ""
}

<#
.SYNOPSIS Reads ports.json and returns default config.
Side effects: none. Falls back to defaults if file is missing.
Returns hashtable with keys: ollama, comfyui, openwebui, listen (string).
#>
<#
.SYNOPSIS Shows version info and exits.
No side effects. Reads version from system_config.json or falls back to script header.
#>
function Show-Version {
    $configPath = "${Root}\AI_CONFIG\system_config.json"
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($cfg.architecture_version) {
            Write-Host "ai-ai-ai $($cfg.architecture_version)"
            return
        }
    }
    Write-Host "ai-ai-ai v0.1.2"
}

function Get-PortConfig {
    $portFile = "${Root}\AI_CONFIG\ports.json"
    $defaults = @{ollama=11434; comfyui=8188; openwebui=3000; listen="0.0.0.0"}
    if (Test-Path $portFile) {
        $saved = Get-Content $portFile -Raw | ConvertFrom-Json
        $keys = @($defaults.Keys)
        foreach ($key in $keys) {
            $val = $saved.$key
            if ($key -eq "listen" -and $val) { $defaults.$key = $val }
            elseif ($val -and $val -gt 0) { $defaults.$key = [int]$val }
        }
    }
    return $defaults
}

<#
.SYNOPSIS Starts, stops, or checks ComfyUI status.
.Parameter Action Valid values: "start", "stop", "status".
Side effects (start): regenerates launcher with current port/listen/GPU flag,
starts a hidden PowerShell process. Requires ComfyUI to be installed.
#>
function Manage-ComfyUI {
    param([string]$Action)
    $ports = Get-PortConfig
    $launcher = "${Root}\AI_TOOLS\launch_comfyui.ps1"
    $comfyPort = $ports.comfyui
    $comfyHost = $ports.listen
    $comfyRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${comfyPort} "

    # Read backend from system_config.json for launcher generation
    $configPath = "${Root}\AI_CONFIG\system_config.json"
    $comfyuiBackend = "directml"
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($cfg.comfyui_backend) { $comfyuiBackend = $cfg.comfyui_backend }
    }

    switch ($Action) {
        "start" {
            if ($comfyRunning) { return }
            if (!(Test-Path $launcher)) {
                Write-Host "ComfyUI not installed. Run: ai install comfyui"
                exit 1
            }
            # Regenerate launcher with current listen address
            $gpu = Get-GPUType
            $activatePath = if ($gpu -eq "amd" -and $comfyuiBackend -eq "rocm") { ".\venv_rocm\Scripts\Activate.ps1" } else { ".\venv\Scripts\Activate.ps1" }
            $gpuFlag = if ($gpu -eq "amd" -and $comfyuiBackend -ne "rocm") { " --directml" } else { "" }
            $comfyPath = "${Root}\AI_CORE\Apps\ComfyUI"
            $logDir = "${Root}\AI_CACHE\logs"
            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            $launcherContent = @"
`$logFile = "$logDir\comfyui.log"
Set-Location "$comfyPath"
$activatePath
python main.py --listen $comfyHost --port $comfyPort --output-directory "${Root}\AI_WORKSPACE\output" --temp-directory "${Root}\AI_CACHE\comfyui_temp" --use-pytorch-cross-attention --disable-smart-memory --bf16-unet$gpuFlag *>&1 | ForEach-Object { "`$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff') `$_" } | Out-File "`$logFile" -Append
"@
            $launcherContent | Out-File $launcher -Encoding utf8
            # Rotate log so error output reflects only this session
            Rotate-LogFile "$logDir\comfyui.log"
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
            # Wait for service with retries (cold starts can take 15-30s)
            # Service starts in background — use ai status or ai watch to check readiness
            Write-Host "ComfyUI starting..."
        }
        "stop" {
            if (-not $comfyRunning) { return }
            # Find PID listening on port 8188
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${comfyPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                # Wait for process to exit and release file handles
                $timeout = 10
                while ($timeout -gt 0 -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                    Start-Sleep -Seconds 1; $timeout--
                }
                if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
                    Write-Host "ERROR: Could not stop ComfyUI. Close it manually and try again."
                    exit 1
                }
                Write-Host "ComfyUI stopped."
            } else {
                Write-Host "Could not find ComfyUI process."
            }
        }
        "status" {
            if ($comfyRunning) {
                Write-Host "ComfyUI: Running on port $comfyPort — http://$($comfyHost):$comfyPort"
            } else {
                Write-Host "ComfyUI: not running"
            }
        }
    }
}

function Manage-Ollama {
    param([string]$Action)
    $ports = Get-PortConfig
    $ollamaPort = $ports.ollama
    $ollamaHost = $ports.listen
    $ollamaRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${ollamaPort} "

    switch ($Action) {
        "start" {
            if ($ollamaRunning) { return }
            # Generate launcher with listen address
            $ollamaLauncher = "${Root}\AI_TOOLS\launch_ollama.ps1"
            $logDir = "${Root}\AI_CACHE\logs"
            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            $launcher = @"
`$logFile = "$logDir\ollama.log"
`$env:OLLAMA_HOST = "${ollamaHost}:${ollamaPort}"
ollama serve *>&1 | ForEach-Object { "`$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff') `$_" } | Out-File "`$logFile" -Append
"@
            $launcher | Out-File $ollamaLauncher -Encoding utf8
            Rotate-LogFile "$logDir\ollama.log"
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ollamaLauncher`""
            # Wait for service with retries
            Write-Host "Ollama starting..."
        }
        "stop" {
            if (-not $ollamaRunning) { return }
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${ollamaPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                # Wait for process to exit and release file handles
                $timeout = 10
                while ($timeout -gt 0 -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                    Start-Sleep -Seconds 1; $timeout--
                }
                if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
                    Write-Host "ERROR: Could not stop Ollama. Close it manually and try again."
                    exit 1
                }
                Write-Host "Ollama stopped."
            } else {
                Write-Host "Could not find Ollama process."
            }
        }
        "status" {
            if ($ollamaRunning) {
                Write-Host "Ollama: Running on port $ollamaPort — http://$($ollamaHost):$ollamaPort"
            } else {
                Write-Host "Ollama: not running"
            }
        }
    }
}

function Manage-WebUI {
    param([string]$Action)
    $ports = Get-PortConfig
    $webuiPath = "${Root}\AI_CORE\Apps\open-webui"
    $webuiLauncher = "${Root}\AI_TOOLS\launch_openwebui.ps1"
    $webuiPort = $ports.openwebui
    $webuiHost = $ports.listen
    $webuiRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${webuiPort} "

    switch ($Action) {
        "start" {
            if ($webuiRunning) { return }
            if (!(Test-Path $webuiPath)) {
                Write-Host "Open Web UI not installed. Run: ai install openwebui"
                exit 1
            }
            # Regenerate launcher with current listen address
            $logDir = "${Root}\AI_CACHE\logs"
            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            $launcher = @"
`$logFile = "$logDir\openwebui.log"
`$webuiPath = "$webuiPath"
`$portFile = "`${webuiPath}\..\..\..\AI_CONFIG\ports.json"
`$port = 3000
`$hostAddr = "$webuiHost"
if (Test-Path `$portFile) {
    `$cfg = Get-Content `$portFile | ConvertFrom-Json
    if (`$cfg.openwebui -and `$cfg.openwebui -gt 0) { `$port = `$cfg.openwebui }
    if (`$cfg.listen) { `$hostAddr = `$cfg.listen }
}
Set-Location "`$webuiPath"
.\venv\Scripts\Activate.ps1
open-webui serve --host `$hostAddr --port `$port *>&1 | ForEach-Object { "`$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff') `$_" } | Out-File "`$logFile" -Append
"@
            $launcher | Out-File $webuiLauncher -Encoding utf8
            Rotate-LogFile "$logDir\openwebui.log"
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$webuiLauncher`""
            # Wait for service with retries (Alembic migrations can be slow)
            Write-Host "Open Web UI starting..."
        }
        "stop" {
            if (-not $webuiRunning) { return }
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${webuiPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                # Wait for process to exit and release file handles
                $timeout = 10
                while ($timeout -gt 0 -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                    Start-Sleep -Seconds 1; $timeout--
                }
                if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
                    Write-Host "ERROR: Could not stop Open Web UI. Close it manually and try again."
                    exit 1
                }
                Write-Host "Open Web UI stopped."
            } else {
                Write-Host "Could not find process for Open Web UI."
            }
        }
        "status" {
            if ($webuiRunning) {
                Write-Host "Open Web UI: Running on port $webuiPort — http://$($webuiHost):$webuiPort"
            } else {
                Write-Host "Open Web UI: not running"
            }
        }
    }
}

<#
.SYNOPSIS Rotates a log file: zips if from a previous day, starts fresh.
Keeps archives for 7 days in <logdir>\archive\. Idempotent if already rotated.
#>
function Rotate-LogFile {
    param([string]$Path)
    if (!(Test-Path $Path)) { return }
    $lastWrite = (Get-Item $Path).LastWriteTime
    $archiveDir = "$(Split-Path $Path -Parent)\archive"
    $baseName = (Get-Item $Path).BaseName
    $archiveName = "$archiveDir\$($baseName)_$($lastWrite.ToString('yyyyMMdd')).zip"
    if (!(Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }
    Compress-Archive -Path $Path -DestinationPath $archiveName -Force
    Remove-Item $Path -Force
    # Clean archives older than 7 days
    $pattern = "$archiveDir\$($baseName)_*.zip"
    Get-ChildItem $pattern -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
}
<#
.SYNOPSIS Tails the log file for a given service. Uses Get-Content -Wait for live output.
Ctrl+C to exit.
#>
function Show-Watch {
    param([string]$Service)
    $logDir = "${Root}\AI_CACHE\logs"
    $logFiles = @{
        comfyui   = "$logDir\comfyui.log"
        ollama    = "$logDir\ollama.log"
        openwebui = "$logDir\openwebui.log"
    }
    $logFile = $logFiles[$Service]
    if (-not $logFile) {
        Write-Host "Usage: ai watch <comfyui|ollama|openwebui>"
        exit 1
    }
    if (!(Test-Path $logFile)) {
        Write-Host "No log file found for $Service. Start the service first."
        exit 1
    }
    Write-Host "Watching $Service log (Ctrl+C to exit)..."
    Get-Content -Path $logFile -Tail 30 -Wait
}

function Get-GPUType {
    # Check for NVIDIA
    $nvidia = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
    if ($nvidia) {
        return "nvidia"
    }

    # Check for AMD
    $amd = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "AMD|Radeon" }
    if ($amd) {
        return "amd"
    }

    return "unknown"
}

<#
.SYNOPSIS Detects AMD GPU generation from the device name.
Returns "rdna1" (RX 5000 series), "rdna2" (RX 6000), "rdna3plus" (RX 7000+),
or $null if not an AMD GPU.
#>
function Get-AMDGen {
    $amdGpu = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "AMD|Radeon" }
    if (-not $amdGpu) { return $null }
    if ($amdGpu.Name -match "RX (\d)\d{3}") {
        $series = [int]$Matches[1]
        if ($series -ge 7) { return "rdna3plus" }
        if ($series -eq 6) { return "rdna2" }
        if ($series -eq 5) { return "rdna1" }
    }
    return $null
}

function Install-ComfyUI {
    param([string]$Backend = "")
    Manage-ComfyUI "stop"
    Push-Location
    $ComfyPath = "$Root\AI_CORE\Apps\ComfyUI"
    $gpu = Get-GPUType

    Write-Host "□ Checking ComfyUI..."

    $freshInstall = $false
    if (!(Test-Path $ComfyPath)) {
        git clone https://github.com/comfyanonymous/ComfyUI.git "$ComfyPath" 2>$null
        $freshInstall = $true
    } else {
            Write-Host "  ✓ Checking for updates..."
            $pullResult = git pull 2>&1
            if ($pullResult -match "Already up to date") {
            Write-Host "  ✓ Up to date"
        } else {
            Write-Host "  ✓ Updated"
        }
    }

    Set-Location "$ComfyPath"

    # Backend selection for AMD
    if ($gpu -eq "amd") {
        $amdGen = Get-AMDGen
        if ([string]::IsNullOrEmpty($Backend)) {
            # Read existing backend from config to avoid re-prompting on upgrades
            $existingCfg = $null
            if (Test-Path "$Root\AI_CONFIG\system_config.json") {
                $existingCfg = Get-Content "$Root\AI_CONFIG\system_config.json" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            if ($existingCfg -and $existingCfg.comfyui_backend -eq "rocm") {
                $Backend = "rocm"
                if ($freshInstall) { Write-Host "  Using existing ROCm backend" }
            } elseif ($existingCfg -and $existingCfg.comfyui_backend -eq "directml") {
                $Backend = "directml"
                if ($freshInstall) { Write-Host "  Using existing DirectML backend" }
            } elseif ($amdGen -eq "rdna1") {
                $Backend = "directml"
                Write-Host "  DirectML selected (ROCm not available on this GPU)"
            } else {
                # Auto-select ROCm on RDNA2+ hardware
                $Backend = "rocm"
                if ($freshInstall) { Write-Host "  Auto-selected ROCm backend (pass -Backend directml to override)" }
            }
        }
        # Re-check: refuse ROCm on unsupported hardware
        if ($Backend -eq "rocm" -and $amdGen -eq "rdna1") {
            Write-Host "WARNING: ROCm is not available on RX 5000 series (RDNA1). Falling back to DirectML."
            $Backend = "directml"
        }
        if ([string]::IsNullOrEmpty($Backend)) { $Backend = "directml" }
        if ($Backend -ne "directml" -and $Backend -ne "rocm") {
            Write-Host "WARNING: Unknown backend '$Backend', defaulting to directml"
            $Backend = "directml"
        }
    }

    $venvName = if ($Backend -eq "rocm") { "venv_rocm" } else { "venv" }
    $pythonVer = if ($Backend -eq "rocm") { "3.12" } else { "3.11" }

    # Venv creation
    if ($gpu -eq "nvidia") {
        if (!(Test-Path ".\venv")) {
            if ($freshInstall) { Write-Host "  Creating Python 3.11 environment..." }
            py -3.11 -m venv venv
        }
    } elseif ($Backend -eq "rocm") {
        if (!(Test-Path ".\venv_rocm")) {
            if ($freshInstall) { Write-Host "  Creating Python $pythonVer environment..." }
            py -3.12 -m venv venv_rocm
        }
    } else {
        $recreateVenv = $false
        if ((Test-Path ".\venv") -and $gpu -eq "amd") {
            $dmlCheck = & ".\venv\Scripts\python.exe" -c "import torch_directml; print('ok')" 2>$null
            if ($dmlCheck -ne "ok") {
                if ($freshInstall) { Write-Host "  DirectML backend not found, recreating venv" }
                $recreateVenv = $true
            }
        }
        if ($recreateVenv -or !(Test-Path ".\venv")) {
            if ($recreateVenv) { Remove-Item -Recurse -Force ".\venv" }
            if ($freshInstall) { Write-Host "  Creating Python $pythonVer environment..." }
            py -3.11 -m venv venv
        }
    }

    # pip install
    Write-Host "  ✓ Checking Python dependencies..."
    if ($gpu -eq "nvidia") {
        .\venv\Scripts\Activate.ps1
        pip install -r requirements.txt 2>&1 | Out-Null
        deactivate
    } elseif ($Backend -eq "rocm") {
        .\venv_rocm\Scripts\Activate.ps1
        if ($freshInstall) { Write-Host "  Installing ROCm stack..." }
        pip install --no-cache-dir `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_core-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm-7.2.1.tar.gz 2>&1 | Out-Null
        pip install --no-cache-dir `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl 2>&1 | Out-Null
        pip install -r requirements.txt 2>&1 | Out-Null
        pip install --no-cache-dir --force-reinstall --no-deps `
            https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl 2>&1 | Out-Null
        if ($freshInstall) { Write-Host "  ROCm stack ready" }
        deactivate
    } else {
        .\venv\Scripts\Activate.ps1
        Write-Host "AMD GPU — installing DirectML stack..."
        pip install torch-directml 2>&1 | Out-Null
        pip install -r requirements.txt 2>&1 | Out-Null
        Write-Host "  Patching torchaudio for DirectML (removing CUDA stubs)..."
        pip install torchaudio --force-reinstall --no-deps --no-cache-dir --index-url https://download.pytorch.org/whl/cpu 2>&1 | Out-Null
        $extDir = "$ComfyPath\venv\Lib\site-packages\torchaudio\_extension"
        if (Test-Path $extDir) { Remove-Item -Recurse -Force $extDir }
        New-Item -Path "$ComfyPath\venv\Lib\site-packages\torchaudio\_extension" -ItemType Directory -Force | Out-Null
        @"
_IS_TORCHAUDIO_EXT_AVAILABLE = False
def fail_if_no_align(f): return f
def _init_extension(): pass
def _load_lib(*a): return False
"@ | Set-Content -Path "$ComfyPath\venv\Lib\site-packages\torchaudio\_extension\__init__.py"
        Write-Host "  DirectML stack ready (torchaudio patched)"
        deactivate
    }

    Write-Host "  ✓ Up to date"

    # Update config with detected GPU and backend
    $configPath = "$Root\AI_CONFIG\system_config.json"
    $config = $null
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    if (-not $config) { $config = New-Object PSObject }
    $config | Add-Member -MemberType NoteProperty -Name "gpu" -Value $gpu -Force
    if ($gpu -eq "amd") {
        $config | Add-Member -MemberType NoteProperty -Name "comfyui_backend" -Value $Backend -Force
    }
    $config | ConvertTo-Json -Depth 10 | Out-File $configPath
    if ($freshInstall) {
        Write-Host "  Config: gpu=$gpu"
        if ($gpu -eq "amd") { Write-Host "  Backend: $Backend" }
    }

    # Ensure vault directories exist
    $vaultDirs = @(
        "$Root\AI_VAULT\models\diffusion\checkpoints",
        "$Root\AI_VAULT\models\diffusion\diffusion_models",
        "$Root\AI_VAULT\models\diffusion\loras",
        "$Root\AI_VAULT\models\diffusion\vae",
        "$Root\AI_VAULT\models\diffusion\controlnet",
        "$Root\AI_VAULT\models\diffusion\unet",
        "$Root\AI_VAULT\models\diffusion\text_encoders",
        "$Root\AI_VAULT\models\diffusion\upscale_models",
        "$Root\AI_VAULT\models\diffusion\ipadapter",
        "$Root\AI_VAULT\models\diffusion\style_models",
        "$Root\AI_VAULT\models\diffusion\clip_vision",
        "$Root\AI_VAULT\models\diffusion\clip",
        "$Root\AI_VAULT\models\embeddings"
    )
    foreach ($d in $vaultDirs) {
        if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # Extra model paths
    $yaml = @"
vault_config:
    checkpoints: $Root\AI_VAULT\models\diffusion\checkpoints
    diffusion_models: $Root\AI_VAULT\models\diffusion\diffusion_models
    loras: $Root\AI_VAULT\models\diffusion\loras
    vae: $Root\AI_VAULT\models\diffusion\vae
    controlnet: $Root\AI_VAULT\models\diffusion\controlnet
    unet: $Root\AI_VAULT\models\diffusion\unet
    text_encoders: $Root\AI_VAULT\models\diffusion\text_encoders
    upscale_models: $Root\AI_VAULT\models\diffusion\upscale_models
    ipadapter: $Root\AI_VAULT\models\diffusion\ipadapter
    style_models: $Root\AI_VAULT\models\diffusion\style_models
    clip_vision: $Root\AI_VAULT\models\diffusion\clip_vision
    clip: $Root\AI_VAULT\models\diffusion\clip
    embeddings: $Root\AI_VAULT\models\embeddings
"@
    $yaml | Out-File "$ComfyPath\extra_model_paths.yaml" -Encoding utf8

    if ($freshInstall) {
        # Quick validation
        Write-Host "  Validating model paths..."
        $yamlLines = Get-Content "$ComfyPath\extra_model_paths.yaml"
        $firstLine = $yamlLines[0].Trim()
        if ($firstLine -match "^[a-zA-Z_]+:$" -and $yamlLines.Count -gt 1 -and $yamlLines[1] -match "^\s+[a-zA-Z_]+:") {
            Write-Host "  OK"
        } else {
            Write-Host "  WARNING: format may be wrong — dumping file:"
            $yamlLines | ForEach-Object { Write-Host "    >$_<" }
        }
    }

    # Launcher with GPU flag and listen address
    $activatePath = if ($gpu -eq "amd" -and $Backend -eq "rocm") { ".\venv_rocm\Scripts\Activate.ps1" } else { ".\venv\Scripts\Activate.ps1" }
    $gpuFlag = if ($gpu -eq "amd" -and $Backend -ne "rocm") { " --directml" } else { "" }
    $portCfg = Get-PortConfig
    $listenAddr = $portCfg.listen
    $comfyPort = $portCfg.comfyui
    $logDir = "${Root}\AI_CACHE\logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $launcher = @"
`$logFile = "$logDir\comfyui.log"
Set-Location "$ComfyPath"
$activatePath
python main.py --listen $listenAddr --port $comfyPort --output-directory "${Root}\AI_WORKSPACE\output" --temp-directory "${Root}\AI_CACHE\comfyui_temp" --use-pytorch-cross-attention --disable-smart-memory --bf16-unet$gpuFlag *>&1 | ForEach-Object { "`$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff') `$_" } | Out-File "`$logFile" -Append
"@
    # Ensure target directory exists
    $toolsDir = "${Root}\AI_TOOLS"
    if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }

    $launcher | Out-File "${Root}\AI_TOOLS\launch_comfyui.ps1" -Encoding utf8

    if ($freshInstall) {
        Write-Host ""
        Write-Host "ComfyUI ready ($gpu). Launch with: .\AI_TOOLS\launch_comfyui.ps1"
    }
    Pop-Location
}

function Install-ComfyUI-Manager {
    Write-Host "□ Checking ComfyUI-Manager..."
    Manage-ComfyUI "stop"
    Push-Location
    $nodeDir = "${Root}\AI_CORE\Apps\ComfyUI\custom_nodes\ComfyUI-Manager"
    if (!(Test-Path $nodeDir)) {
        Write-Host "Installing ComfyUI-Manager..."
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$nodeDir"
        Write-Host "ComfyUI-Manager installed. Restart ComfyUI to see it."
    } else {
        Set-Location "$nodeDir"
        Write-Host "  ✓ Checking for updates..."
        $pullResult = git pull 2>&1
        if ($pullResult -notmatch "Already up to date") {
            Write-Host "  ✓ Updated — restart ComfyUI"
        } else {
            Write-Host "  ✓ Up to date"
        }
    }
    Pop-Location
}

<#
.SYNOPSIS Installs Ollama via winget.
Side effects: requires admin rights (winget). May trigger UAC prompt.
Does NOT set OLLAMA_MODELS env var. Run 'ai setup env' after install.
Idempotent: winget handles upgrades.
#>
function Install-Ollama {
    Manage-Ollama "stop"
    Write-Host "□ Checking Ollama..."
    winget install Ollama.Ollama --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Installed" } else { Write-Host "  ✓ Up to date" }
    $ollamaModels = [Environment]::GetEnvironmentVariable("OLLAMA_MODELS", "User")
    if (-not $ollamaModels) {
        Write-Host "(Run 'ai setup env' to set OLLAMA_MODELS)"
    }
}

function Install-OpenWebUI {
    Manage-WebUI "stop"
    Push-Location
    $webuiPath = "${Root}\AI_CORE\Apps\open-webui"
    $webuiVenv = "${webuiPath}\venv"

    if (!(Test-Path $webuiPath)) {
        New-Item -ItemType Directory -Path $webuiPath -Force | Out-Null
    }

    Set-Location "$webuiPath"

    if (!(Test-Path $webuiVenv)) {
        Write-Host "Creating Python environment..."
        py -3.11 -m venv venv
    }

    $freshInstall = -not (Test-Path $webuiVenv)

    Write-Host "□ Checking Open Web UI..."
    .\venv\Scripts\Activate.ps1
    pip install open-webui 2>&1 | Out-Null
    deactivate

    if ($freshInstall) { Write-Host "  ✓ Installed" } else { Write-Host "  ✓ Up to date" }

    # Launcher that reads port and listen address from config
    $logDir = "${Root}\AI_CACHE\logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $launcher = @"
`$logFile = "$logDir\openwebui.log"
`$webuiPath = "$webuiPath"
`$portFile = "`${webuiPath}\..\..\..\AI_CONFIG\ports.json"
`$port = 3000
`$hostAddr = "0.0.0.0"
if (Test-Path `$portFile) {
    `$cfg = Get-Content `$portFile | ConvertFrom-Json
    if (`$cfg.openwebui -and `$cfg.openwebui -gt 0) { `$port = `$cfg.openwebui }
    if (`$cfg.listen) { `$hostAddr = `$cfg.listen }
}
Set-Location "`$webuiPath"
.\venv\Scripts\Activate.ps1
open-webui serve --host `$hostAddr --port `$port *>&1 | ForEach-Object { "`$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff') `$_" } | Out-File "`$logFile" -Append
"@

    $toolsDir = "${Root}\AI_TOOLS"
    if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
    $launcher | Out-File "${Root}\AI_TOOLS\launch_openwebui.ps1" -Encoding utf8

    $defaultPort = (Get-PortConfig).openwebui
    if ($freshInstall) {
        Write-Host "Open Web UI installed."
        Write-Host "  Location: $webuiPath"
        Write-Host "  Launch: ${Root}\AI_TOOLS\launch_openwebui.ps1"
        Write-Host "  URL: http://127.0.0.1:$defaultPort"
        if ($defaultPort -ne 3000) {
            Write-Host "  Port set via AI_CONFIG\ports.json (default is 3000)"
        }
    }
    Pop-Location
}

<#
.SYNOPSIS Displays the service dashboard: status, ports, CPU, RAM, GPU, model counts.
Side effects: runs netstat, Get-CimInstance (CPU/RAM), Get-Counter (GPU).
GPU data may be unavailable on some AMD drivers (falls back to name + total VRAM).
Service status determined by port listening, not process name.
Only shows services installed through 'ai install' (checks AI_CORE paths).
#>
function Show-Status {
    $ports = Get-PortConfig
    $configPath = "$Root\AI_CONFIG\system_config.json"
    $gpu = "unknown"
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath | ConvertFrom-Json
        $detected = Get-GPUType
        $gpu = if ($detected -ne "unknown") { $detected.ToUpper() } else { $cfg.gpu.ToUpper() }
    }

    Write-Host "┌──────────────┬─────────┬────────┐"
    Write-Host "│ Service      │ Status  │ Port   │"
    Write-Host "├──────────────┼─────────┼────────┤"

    $services = @(
        @{Name="Ollama";    Port=$ports.ollama;    Path="$Root\AI_VAULT\models\llm"},
        @{Name="ComfyUI";   Port=$ports.comfyui;   Path="$Root\AI_CORE\Apps\ComfyUI"},
        @{Name="OpenWebUI"; Port=$ports.openwebui; Path="$Root\AI_CORE\Apps\open-webui"}
    )
    foreach ($svc in $services) {
        $running = netstat -an 2>$null | Select-String "LISTENING" | Select-String ":$($svc.Port) "
        $installed = Test-Path $svc.Path
        $status = if ($installed -and $running) { "Started" } elseif ($installed) { "Stopped" } else { "──" }
        $portTxt = if ($installed) { $svc.Port.ToString() } else { "──" }
        Write-Host ("│ {0,-12} │ {1,-7} │ {2,-6} │" -f $svc.Name, $status, $portTxt)
    }
    Write-Host "└──────────────┴─────────┴────────┘"
    Write-Host ""

    # System resources
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $os = Get-CimInstance Win32_OperatingSystem
    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramUsed = [math]::Round($ramTotal - $ramFree, 1)
    $ramPct = [math]::Round(($ramUsed / $ramTotal) * 100)
    Write-Host "CPU:  $cpu%"
    Write-Host "RAM:  $ramUsed/$ramTotal GB ($ramPct%)"

    # GPU — name from WMI, total VRAM from registry (more accurate on AMD)
    $gpuUtil = $null
    $gpuVramUsed = $null
    $gpuVramTotal = $null
    $gpuName = $null

    $gpuInfo = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gpuInfo) {
        $gpuName = $gpuInfo.Name
        # Total VRAM — try registry (accurate on AMD), fall back to WMI
        $vramBytes = $null
        $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
            $mem = (Get-ItemProperty $_.PSPath -Name "HardwareInformation.qwMemorySize" -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
            if ($mem -and $mem -gt $vramBytes) { $vramBytes = $mem }
        }
        if (-not $vramBytes) {
            $vramBytes = try {
                Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
                $factory = [Windows.Graphics.Dxgi.DirectX]::CreateDXGIFactory1()
                $adapter = $factory.EnumAdapters(0)
                $adapter.Description.DedicatedVideoMemory
            } catch { $null }
        }
        $gpuVramTotal = if ($vramBytes -and $vramBytes -gt 0) { [math]::Round($vramBytes / 1GB, 1) } elseif ($gpuInfo.AdapterRAM -gt 0) { [math]::Round($gpuInfo.AdapterRAM / 1GB, 1) } else { $null }
    }

    # GPU utilization — use timeout-safe job (Get-Counter can hang on some AMD drivers)
    $gpuUtil = $null
    $job = Start-Job -ScriptBlock {
        param($c) Get-Counter $c -ErrorAction SilentlyContinue |
            ForEach-Object { $_.CounterSamples } |
            Where-Object { $_.Path -notmatch "_Total|engine" } |
            Measure-Object -Property CookedValue -Average |
            Select-Object -ExpandProperty Average
    } -ArgumentList "\GPU(*)\Utilization Percentage"
    $gpuUtil = Wait-Job $job -Timeout 3 | Receive-Job
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue

    if ($gpuUtil -eq $null -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        $gpuUtil = nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null
    }
    # VRAM usage — timeout-safe job (can hang on some AMD drivers)
    $gpuVramUsed = $null
    $job = Start-Job -ScriptBlock {
        param($c) Get-Counter $c -ErrorAction SilentlyContinue |
            ForEach-Object { $_.CounterSamples } |
            Where-Object { $_.Path -notmatch "_Total" } |
            Measure-Object -Property CookedValue -Sum |
            Select-Object -ExpandProperty Sum
    } -ArgumentList "\GPU Adapter Memory\Dedicated Usage"
    $gpuVramUsed = Wait-Job $job -Timeout 3 | Receive-Job
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($gpuVramUsed -eq $null) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct DXGI_QUERY_VIDEO_MEMORY_INFO {
    public ulong Budget;
    public ulong CurrentUsage;
    public ulong AvailableForReservation;
    public ulong CurrentReservation;
}

[Guid("645967A4-1392-4310-A798-8053CE5E93DA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[ComImport]
interface IDXGIAdapter3 {
    void QueryInterface();
    void AddRef();
    void Release();
    void SetPrivateData();
    void SetPrivateDataInterface();
    void GetParent();
    void EnumOutputs();
    void GetDesc();
    void GetDesc1();
    void GetDesc2();
    void RegisterHardwareContentProtectionTeardownStatusEvent();
    void UnregisterHardwareContentProtectionTeardownStatus();
    void QueryVideoMemoryInfo(uint NodeIndex, int MemorySegmentGroup, out DXGI_QUERY_VIDEO_MEMORY_INFO pVideoMemoryInfo);
    void RegisterVideoMemoryBudgetChangeNotificationEvent();
    void UnregisterVideoMemoryBudgetChangeNotification();
}

[Guid("7b7166ec-21c7-44ae-b21a-c9ae321ae369"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[ComImport]
interface IDXGIFactory1 {
    void QueryInterface();
    void AddRef();
    void Release();
    void SetPrivateData();
    void SetPrivateDataInterface();
    void GetParent();
    void EnumAdapters();
    void MakeWindowAssociation();
    void GetWindowAssociation();
    void CreateSwapChain();
    void CreateSoftwareAdapter();
    void EnumAdapters1(uint Adapter, [MarshalAs(UnmanagedType.IUnknown)] out object ppAdapter);
}

public class DxVram {
    [DllImport("dxgi.dll", EntryPoint = "CreateDXGIFactory1")]
    static extern int CreateDXGIFactory1Native([MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppFactory);

    public static ulong GetVramUsage() {
        object factoryObj = null;
        try {
            int hr = CreateDXGIFactory1Native(typeof(IDXGIFactory1).GUID, out factoryObj);
            if (hr != 0) return 0;
            IDXGIFactory1 factory = (IDXGIFactory1)factoryObj;
            object adapterObj = null;
            factory.EnumAdapters1(0, out adapterObj);
            if (adapterObj == null) return 0;
            IDXGIAdapter3 adapter3 = (IDXGIAdapter3)adapterObj;
            DXGI_QUERY_VIDEO_MEMORY_INFO info;
            adapter3.QueryVideoMemoryInfo(0, 0, out info);
            return info.CurrentUsage;
        } catch { return 0; } finally {
            if (factoryObj != null) Marshal.ReleaseComObject(factoryObj);
        }
    }
}
'@ -ErrorAction Stop
            $dxgiVram = [DxVram]::GetVramUsage()
            if ($dxgiVram -gt 0) { $gpuVramUsed = $dxgiVram }
        } catch { }
    }

    if ($gpuUtil) {
        Write-Host "GPU:  $([math]::Round([double]$gpuUtil))%  —  $gpuName"
        if ($gpuVramUsed -and $gpuVramTotal) {
            Write-Host "VRAM: $([math]::Round($gpuVramUsed / 1GB, 1))/$gpuVramTotal GB"
        } elseif ($gpuVramUsed) {
            Write-Host "VRAM: $([math]::Round($gpuVramUsed / 1GB, 1)) GB used"
        } elseif ($gpuVramTotal) {
            Write-Host "VRAM: 0/$gpuVramTotal GB"
        }
    } else {
        if ($gpuName) {
            $gpuLine = "GPU:  $gpuName"
            if ($gpuVramUsed -and $gpuVramTotal) {
                $gpuLine += "  | VRAM: $([math]::Round($gpuVramUsed / 1GB, 1))/$gpuVramTotal GB"
            } elseif ($gpuVramTotal) {
                $gpuLine += "  ($gpuVramTotal GB)"
            } elseif ($gpuVramUsed) {
                $gpuLine += "  | VRAM: $([math]::Round($gpuVramUsed / 1GB, 1)) GB used"
            }
            Write-Host $gpuLine
        } else { Write-Host "GPU:  not detected" }
    }
    Write-Host ""

    # Models summary
    $llmDir = "$Root\AI_VAULT\models\llm"
    $diffDir = "$Root\AI_VAULT\models\diffusion"
    $embedDir = "$Root\AI_VAULT\models\embeddings"
    # Ollama models — only query if service is running (avoids update popup)
    $ollamaModels = @()
    $ollamaScanned = $false
    $ollamaPort = (Get-PortConfig).ollama
    if (netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${ollamaPort} ") {
        $job = Start-Job -ScriptBlock { ollama list 2>$null | Select-Object -Skip 1 }
        $ollamaRows = Wait-Job $job -Timeout 3 | Receive-Job
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
        $ollamaModels = @($ollamaRows | ForEach-Object { $parts = $_ -split '\s{2,}'; if ($parts.Count -ge 1) { $parts[0] -replace ':latest','' } })
        $ollamaScanned = $true
    }
    $llmCount = $ollamaModels.Count
    $diffCount = if (Test-Path $diffDir) { @(Get-ChildItem $diffDir -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count } else { 0 }
    $vaeCount = if (Test-Path "$diffDir\vae") { @(Get-ChildItem "$diffDir\vae" -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count } else { 0 }
    Write-Host ""
    Write-Host "  Models:"
    Write-Host "    LLMs:        $(if ($ollamaScanned) { $llmCount } else { \"Not scanned — service offline\" })"
    Write-Host "    Diffusion:   $diffCount"
    Write-Host "    VAEs:        $vaeCount"

    Write-Host ""

    # Folder health — only show issues
    $missing = @()
    foreach ($layer in @("AI_CONFIG","AI_CORE","AI_VAULT","AI_WORKSPACE","AI_TOOLS","AI_CACHE")) {
        if (!(Test-Path "$Root\$layer")) { $missing += $layer }
    }
    foreach ($link in @("llm","diffusion","embeddings")) {
        if (!(Test-Path "$Root\AI_CORE\_bindings\$link")) { $missing += "_bindings\$link" }
    }
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Issues:"
        foreach ($m in $missing) { Write-Host "  MISSING: $m" }
    }
}

<#
.SYNOPSIS Displays all models in bordered tables: LLMs from ollama list, then
scans vault diffusion/ subdirectories and embeddings/ for actual files.
Side effects: runs ollama list, Get-ChildItem on vault paths.
Each vault subdirectory gets its own table with Name and Size columns.
#>
function Show-Models {
    $llmDir = "$Root\AI_VAULT\models\llm"
    $diffDir = "$Root\AI_VAULT\models\diffusion"
    $embedDir = "$Root\AI_VAULT\models\embeddings"

    <# .SYNOPSIS Converts bytes to human-readable KB/MB/GB string. #>
    function Format-FileSize($bytes) {
        if ($bytes -ge 1GB) { return "$([math]::Round($bytes / 1GB, 1)) GB" }
        if ($bytes -ge 1MB) { return "$([math]::Round($bytes / 1MB)) MB" }
        if ($bytes -ge 1KB) { return "$([math]::Round($bytes / 1KB)) KB" }
        return "$bytes B"
    }

    # Timeout-safe ollama list — only if service is running
    $rawModels = @()
    $ollamaPort = (Get-PortConfig).ollama
    if (netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${ollamaPort} ") {
        $job = Start-Job -ScriptBlock { ollama list 2>$null | Select-Object -Skip 1 }
        $rawModels = Wait-Job $job -Timeout 3 | Receive-Job
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    $ollamaModels = @($rawModels | ForEach-Object {
        $parts = $_ -split '\s{2,}'
        if ($parts.Count -ge 3) {
            [PSCustomObject]@{Name=($parts[0] -replace ':latest',''); Size=$parts[2]}
        }
    })
    if ($ollamaModels) {
        $maxNameLen = [Math]::Max(5, ($ollamaModels | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum) + 8
        $maxSizeLen = [Math]::Max(4, ($ollamaModels | ForEach-Object { ($_.Size -replace '[^\w. ]','').Length } | Measure-Object -Maximum).Maximum) + 2
        $top = "┌" + ("─" * ($maxNameLen + 2)) + "┬" + ("─" * ($maxSizeLen + 2)) + "┐"
        $header = "│ " + "LLMs".PadRight($maxNameLen) + " │ " + "Size".PadRight($maxSizeLen) + " │"
        $sep = "├" + ("─" * ($maxNameLen + 2)) + "┼" + ("─" * ($maxSizeLen + 2)) + "┤"
        $bot = "└" + ("─" * ($maxNameLen + 2)) + "┴" + ("─" * ($maxSizeLen + 2)) + "┘"
        Write-Host $top
        Write-Host $header
        Write-Host $sep
        foreach ($m in $ollamaModels) {
            Write-Host ("│ {0,-$maxNameLen} │ {1,-$maxSizeLen} │" -f $m.Name, $m.Size)
        }
        Write-Host $bot
        Write-Host ""
    }
    # Scan all vault directories dynamically
    $any = $false
    $vaultDirs = @(
        @{Path=$diffDir; Label="Diffusion"}
        @{Path=$embedDir; Label="Embeddings"}
    )
    foreach ($vd in $vaultDirs) {
        if (!(Test-Path $vd.Path)) { continue }
        $subs = Get-ChildItem $vd.Path -Directory -ErrorAction SilentlyContinue
        foreach ($sub in $subs) {
            $files = Get-ChildItem $sub.FullName -File -ErrorAction SilentlyContinue
            if ($files.Count -eq 0) { continue }
            $any = $true
            $label = "$($vd.Label) ($($sub.Name))"
            $namePad = [Math]::Max($label.Length, ($files | ForEach-Object { $_.BaseName.Length } | Measure-Object -Maximum).Maximum + 2)
            $sizePad = 7
            Write-Host "┌─$("─" * $namePad)─┬─$("─" * $sizePad)─┐"
            Write-Host ("│ {0,-$namePad} │ {1,$sizePad} │" -f $label, "Size")
            Write-Host "├─$("─" * $namePad)─┼─$("─" * $sizePad)─┤"
            foreach ($file in $files) {
                Write-Host ("│ {0,-$namePad} │ {1,$sizePad} │" -f $file.BaseName, (Format-FileSize $file.Length))
            }
            Write-Host "└─$("─" * $namePad)─┴─$("─" * $sizePad)─┘"
            Write-Host ""
        }
        # Also list files directly in the parent (not in subfolders)
        $rootFiles = Get-ChildItem $vd.Path -File -ErrorAction SilentlyContinue
        if ($rootFiles.Count -gt 0) {
            $any = $true
            $label = $vd.Label
            $namePad = [Math]::Max($label.Length, ($rootFiles | ForEach-Object { $_.BaseName.Length } | Measure-Object -Maximum).Maximum + 2)
            $sizePad = 7
            Write-Host "┌─$("─" * $namePad)─┬─$("─" * $sizePad)─┐"
            Write-Host ("│ {0,-$namePad} │ {1,$sizePad} │" -f $label, "Size")
            Write-Host "├─$("─" * $namePad)─┼─$("─" * $sizePad)─┤"
            foreach ($file in $rootFiles) {
                Write-Host ("│ {0,-$namePad} │ {1,$sizePad} │" -f $file.BaseName, (Format-FileSize $file.Length))
            }
            Write-Host "└─$("─" * $namePad)─┴─$("─" * $sizePad)─┘"
            Write-Host ""
        }
    }

    if (-not $any) {
        Write-Host "No models found."
    }
}

<#
.SYNOPSIS Deletes all contents under AI_CACHE subdirectories.
Side effects: removes huggingface/ (HF_HOME), torch/, and comfyui_temp/.
Hugging Face downloads can be tens of GB — pin models you want to
keep to AI_VAULT before running this. In-flight downloads may break.
Does NOT delete the directories themselves, only their contents.
#>
function Clean-Cache {
    $cacheDirs = @(
        "$Root\AI_CACHE\huggingface",
        "$Root\AI_CACHE\torch",
        "$Root\AI_CACHE\comfyui_temp"
    )

    $total = 0
    foreach ($dir in $cacheDirs) {
        if (Test-Path $dir) {
            $size = (Get-ChildItem $dir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 1)
            Remove-Item "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cleaned: $dir ($sizeMB MB)"
            $total += $sizeMB
        }
    }

    Write-Host "Total freed: $total MB"
}

<#
.SYNOPSIS Checks OLLAMA_MODELS, HF_HOME, TORCH_HOME against expected vault paths.
Side effects: prompts user to fix each mismatched variable.
Sets User-level environment variables (persistent, survive reboot).
Does NOT modify current process session — requires PowerShell restart.
Exits with code 1 if any variable is skipped.
#>
function Setup-Env {
    Write-Host "Checking environment variables..."
    Write-Host ""

    $vars = @(
        @{Name="OLLAMA_MODELS"; Expected="${Root}\AI_VAULT\models\llm"; Scope="User"; Help="Controls where Ollama stores models. Set before pulling."},
        @{Name="HF_HOME"; Expected="${Root}\AI_CACHE\huggingface"; Scope="User"; Help="Hugging Face cache in AI_CACHE (cleaned by clean cache — pin to AI_VAULT to keep)."},
        @{Name="TORCH_HOME"; Expected="${Root}\AI_CACHE\torch"; Scope="User"; Help="Keeps PyTorch cache in AI_CACHE, not AI_VAULT."}
    )

    $allOk = $true

    foreach ($v in $vars) {
        $current = [Environment]::GetEnvironmentVariable($v.Name, $v.Scope)
        if ($current -eq $v.Expected) {
            Write-Host "  [OK]  $($v.Name) = $current"
        } elseif ($current) {
            Write-Host "  [MIS] $($v.Name) = $current"
            Write-Host "        Expected: $($v.Expected)"
            Write-Host "        $($v.Help)"
            $choice = Read-Host "        Fix it? (Y/n)"
            if ($choice -ne "n") {
                [Environment]::SetEnvironmentVariable($v.Name, $v.Expected, $v.Scope)
                Write-Host "        Fixed. Restart PowerShell and the service for it to take effect."
            } else {
                $allOk = $false
                Write-Host "        Skipped."
            }
        } else {
            Write-Host "  [MIS] $($v.Name) = (not set)"
            Write-Host "        Expected: $($v.Expected)"
            Write-Host "        $($v.Help)"
            $choice = Read-Host "        Set it now? (Y/n)"
            if ($choice -ne "n") {
                [Environment]::SetEnvironmentVariable($v.Name, $v.Expected, $v.Scope)
                Write-Host "        Set. Restart PowerShell and the service for it to take effect."
            } else {
                $allOk = $false
                Write-Host "        Skipped."
            }
        }
        Write-Host ""
    }

    if (-not $allOk) {
        Write-Host "Some variables were skipped. This may cause issues with model storage and caching."
        exit 1
    }

    Write-Host "All environment variables are correct."
}

<#
.SYNOPSIS Copies ai.ps1 to AI_TOOLS\ and adds it to User PATH.
Side effects: overwrites existing AI_TOOLS\ai.ps1.
Adds to both current session $env:Path and persistent User PATH.
Run once after install to make 'ai' available from any directory.
#>
function Setup-Path {
    $toolsDir = "${Root}\AI_TOOLS"
    $scriptPath = "${toolsDir}\ai.ps1"

    # Copy self to AI_TOOLS
    if (!(Test-Path $toolsDir)) {
        New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    }
    Copy-Item -Path "$PSCommandPath" -Destination "$scriptPath" -Force
    Write-Host "  Copied ai.ps1 to $scriptPath"

    # Add to user PATH (persistent)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*${toolsDir}*") {
        $newPath = "${currentPath};${toolsDir}"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "  Added AI_TOOLS to user PATH (persistent)"
    } else {
        Write-Host "  AI_TOOLS already in user PATH"
    }

    # Also add to current session so it works immediately
    if ($env:Path -notlike "*${toolsDir}*") {
        $env:Path = "${env:Path};${toolsDir}"
        Write-Host "  Added AI_TOOLS to current session PATH"
    }

    Write-Host "  You can now use 'ai' from this window and all future windows."
}

<#
.SYNOPSIS Interactive port and listen address configuration.
Side effects: reads/writes AI_CONFIG\ports.json.
Prompts for each service port and a listen address (0.0.0.0 or 127.0.0.1).
Only writes to file if something changed. Restart services after changes.
#>
function Setup-Ports {
    $portFile = "${Root}\AI_CONFIG\ports.json"
    $defaults = @{ollama=11434; comfyui=8188; openwebui=3000}
    $current = @{}
    $currentListen = $null
    if (Test-Path $portFile) {
        $saved = Get-Content $portFile -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) { $current.$key = $saved.$key }
        if ($saved.listen) { $currentListen = $saved.listen }
    }

    Write-Host "Service Port & Address Configuration"
    Write-Host ""

    $changed = $false
    foreach ($key in $defaults.Keys) {
        $val = if ($current.$key) { $current.$key } else { $defaults.$key }
        $input = Read-Host "$key port (current: $val, Enter to keep)"
        if ($input -match '^\d+$') {
            $current.$key = [int]$input
            $changed = $true
        } else {
            $current.$key = $val
        }
    }

    # Listen address
    $listenVal = if ($currentListen) { $currentListen } else { "0.0.0.0" }
    $listenInput = Read-Host "Listen address (current: $listenVal, 0.0.0.0 for all, 127.0.0.1 for localhost)"
    if ($listenInput -match '^[\d\.]+$') {
        $currentListen = $listenInput
        $changed = $true
    } else {
        $currentListen = $listenVal
    }

    if ($changed) {
        $portConfig = @{}
        foreach ($key in $defaults.Keys) { $portConfig.$key = $current.$key }
        $portConfig.listen = $currentListen
        $portConfig | ConvertTo-Json | Out-File $portFile -Encoding utf8
        Write-Host "Config saved to $portFile"
        Write-Host "Restart services for changes to take effect."
    } else {
        Write-Host "No changes."
    }
}

<#
.SYNOPSIS Full system diagnostics: versions, bindings, env vars, models.
Side effects: runs git, python, ollama, ffmpeg version checks.
Scans AI_CORE paths for installed services.
Checks model symlinks and environment variable correctness.
Prints results in a bordered table.
#>
function Doctor-Check {
    Write-Host "┌──────────────────────┬──────────────────────────────┐"

    $configPath = "$Root\AI_CONFIG\system_config.json"
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath | ConvertFrom-Json
        Write-Host ("│ {0,-20} │ {1,-28} │" -f "Stack", "v$($cfg.architecture_version) ($($cfg.gpu.ToUpper()))")
        Write-Host ("│ {0,-20} │ {1,-28} │" -f "Path", $Root)
        Write-Host ("│ {0,-20} │ {1,-28} │" -f "Control Panel", (Split-Path $PSCommandPath -Parent))
        # ROCm check
        $pyExe = "$Root\AI_CORE\Apps\ComfyUI\venv_rocm\Scripts\python.exe"
        if (Test-Path $pyExe) {
            $rocmOut = & $pyExe -c "import torch; print('ROCm' if torch.cuda.is_available() else 'no GPU')" 2>$null
            Write-Host ("│ {0,-20} │ {1,-28} │" -f "ROCm", $(if ($rocmOut -eq "ROCm") { "avail" } else { $rocmOut }))
        }
    } else {
        Write-Host "│ not initialized      │ run 1-init.ps1"
        return
    }
    Write-Host "├──────────────────────┼──────────────────────────────┤"

    # Git
    $g = git --version 2>$null
    if ($g) { Write-Host ("│ {0,-20} │ {1,-28} │" -f "Git", ($g -replace '^git version (\d+(?:\.\d+)*).*', '$1')) } else { Write-Host ("│ {0,-20} │ {1,-28} │" -f "Git", "FAIL") }

    # Python
    $py10 = if (py -3.10 --version 2>$null) { (py -3.10 --version 2>$null) -replace '^Python (\S+).*', '$1' } else { "WARN" }
    $py11 = if (py -3.11 --version 2>$null) { (py -3.11 --version 2>$null) -replace '^Python (\S+).*', '$1' } else { "FAIL" }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Python 3.10", $py10)
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Python 3.11", $py11)

    # Ollama
    $ollamaVer = if (ollama --version 2>$null) { (ollama --version 2>$null) -replace '^ollama version is (\S+).*', '$1' } else { "FAIL" }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Ollama", $ollamaVer)

    # ComfyUI
    $comfyFile = "$Root\AI_CORE\Apps\ComfyUI\comfyui_version.py"
    $comfyVer = if (Test-Path $comfyFile) { (Select-String -Path $comfyFile -Pattern "__version__\s*=\s*['""]([^'""]+)['""]" | ForEach-Object { $_.Matches.Groups[1].Value }) } else { "WARN" }
    if ($comfyVer -eq "WARN" -and !(Test-Path "$Root\AI_CORE\Apps\ComfyUI")) { $comfyVer = "not installed" }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "ComfyUI", $comfyVer)

    # Open Web UI
    $webuiVer = if (Test-Path "$Root\AI_CORE\Apps\open-webui") { & "$Root\AI_CORE\Apps\open-webui\venv\Scripts\pip.exe" show open-webui 2>$null | Select-String "^Version:" | ForEach-Object { $_ -replace ".*:\s*", "" } } else { "not installed" }
    if (-not $webuiVer) { $webuiVer = "?" }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Open Web UI", $webuiVer)

    # FFmpeg
    $ff = ffmpeg -version 2>$null
    if ($ff) { $ff = ($ff -split "`n")[0] -replace '^ffmpeg version (\d+(?:\.\d+)*).*', '$1'; Write-Host ("│ {0,-20} │ {1,-28} │" -f "FFmpeg", $ff) } else { Write-Host ("│ {0,-20} │ {1,-28} │" -f "FFmpeg", "not found") }
    Write-Host "├──────────────────────┼──────────────────────────────┤"

    # Bindings
    $bindOk = $true
    foreach ($link in @("llm","diffusion","embeddings")) { if (!(Test-Path "$Root\AI_CORE\_bindings\$link")) { $bindOk = $false } }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Model bindings", $(if ($bindOk) { "OK" } else { "MISSING" }))

    # Models
    # Timeout-safe ollama list — only if service is running
    $ollamaCount = 0
    $ollamaPort = (Get-PortConfig).ollama
    if (netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${ollamaPort} ") {
        $job = Start-Job -ScriptBlock { @(ollama list 2>$null | Select-Object -Skip 1).Count }
        $ollamaCount = Wait-Job $job -Timeout 3 | Receive-Job
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    $diffC = @(Get-ChildItem "$Root\AI_VAULT\models\diffusion" -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count
    $llmStr = if ($ollamaCount -eq 0) { "0 LLM(s) (service offline)" } else { "$([int]$ollamaCount) LLM(s)" }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Models", "$llmStr, $diffC diffusion")

    # Environment variables
    $envOk = $true
    $expVault = "$Root\AI_VAULT\models\llm"
    $expCache = "$Root\AI_CACHE"
    if (([Environment]::GetEnvironmentVariable("OLLAMA_MODELS","User")) -ne $expVault) { $envOk = $false }
    if (([Environment]::GetEnvironmentVariable("HF_HOME","User")) -ne "${expCache}\huggingface") { $envOk = $false }
    if (([Environment]::GetEnvironmentVariable("TORCH_HOME","User")) -ne "${expCache}\torch") { $envOk = $false }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Environment vars", $(if ($envOk) { "OK" } else { "MIS" }))

    Write-Host "└──────────────────────┴──────────────────────────────┘"
}

# Dispatch
switch ($Command) {
    "install" {
        switch ($SubCommand) {
            "all"             { Install-ComfyUI; Install-ComfyUI-Manager; Install-Ollama; Install-OpenWebUI }
            "comfyui"         { Install-ComfyUI -Backend $BackendArg }
            "comfyui-manager" { Install-ComfyUI-Manager }
            "ollama"          { Install-Ollama }
            "openwebui"       { Install-OpenWebUI }
            default           { Write-Host "Usage: ai install <all|comfyui|comfyui-manager|ollama|openwebui>" }
        }
    }
    "start"      {
        switch ($SubCommand) {
            "all"       { Manage-Ollama "start"; Manage-ComfyUI "start"; Manage-WebUI "start" }
            "ollama"    { Manage-Ollama "start" }
            "comfyui"   { Manage-ComfyUI "start" }
            "openwebui" { Manage-WebUI "start" }
            default     { Write-Host "Usage: ai start <all|ollama|comfyui|openwebui>" }
        }
    }
    "stop"      {
        switch ($SubCommand) {
            "all"       { Manage-Ollama "stop"; Manage-ComfyUI "stop"; Manage-WebUI "stop" }
            "ollama"    { Manage-Ollama "stop" }
            "comfyui"   { Manage-ComfyUI "stop" }
            "openwebui" { Manage-WebUI "stop" }
            default     { Write-Host "Usage: ai stop <all|ollama|comfyui|openwebui>" }
        }
    }
    "restart"    {
        switch ($SubCommand) {
            "all"       { Manage-Ollama "stop"; Manage-Ollama "start"; Manage-ComfyUI "stop"; Manage-ComfyUI "start"; Manage-WebUI "stop"; Manage-WebUI "start" }
            "ollama"    { Manage-Ollama "stop"; Manage-Ollama "start" }
            "comfyui"   { Manage-ComfyUI "stop"; Manage-ComfyUI "start" }
            "openwebui" { Manage-WebUI "stop"; Manage-WebUI "start" }
            default     { Write-Host "Usage: ai restart <all|ollama|comfyui|openwebui>" }
        }
    }
    "status"     {
        switch ($SubCommand) {
            "ollama"    { Manage-Ollama "status" }
            "comfyui"   { Manage-ComfyUI "status" }
            "openwebui" { Manage-WebUI "status" }
            ""        { Show-Status }
            default   { Write-Host "Usage: ai status [ollama|comfyui|openwebui]" }
        }
    }
    "doctor"     { Doctor-Check }
    "watch"      {
        if ($SubCommand) { Show-Watch $SubCommand }
        else { Write-Host "Usage: ai watch <comfyui|ollama|openwebui>" }
    }
    "list"       {
        if (-not $SubCommand) { Show-Models }
        else { Write-Host "Usage: ai list" }
    }
    "clean"      {
        if ($SubCommand -eq "cache") { Clean-Cache }
        else { Write-Host "Usage: ai clean cache" }
    }
    "setup"      {
        if ($SubCommand -eq "env") { Setup-Env }
        elseif ($SubCommand -eq "path") { Setup-Path }
        elseif ($SubCommand -eq "ports") { Setup-Ports }
        else { Write-Host "Usage: ai setup <env|path|ports>" }
    }
    "version"    { Show-Version }
    "help"       { Show-Help }
    default      { Show-Help }
}