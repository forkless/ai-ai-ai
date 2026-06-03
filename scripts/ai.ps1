<#
Ai, ai, ai! Control Panel v1.1 — daily driver for the Ai Bootstrap system
Usage:  ai <command> [options]

Commands:
  install <app>      Install an AI application (comfyui, comfyui-manager, ollama, openwebui)
  start <service>    Start a service (all, ollama, comfyui, openwebui)
  stop <service>     Stop a service (all, ollama, comfyui, openwebui)
  restart <service>  Restart a service (all, ollama, comfyui, openwebui)
  status [service]   System health or specific service status
  doctor             Full system diagnostics
  models list        List installed models
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

function Show-Help {
    $cmd = "  {0,-26}{1}"
    $boxWidth = 78
    $title = " Ai, ai, ai! Control Panel v1.1 "
    $inner = $boxWidth - 2
    $lPad = [Math]::Max(0, [Math]::Floor(($inner - $title.Length) / 2))
    Write-Host "┌$("─" * $inner)┐"
    Write-Host ("│" + " " * $lPad + $title + " " * ($inner - $lPad - $title.Length) + "│")
    Write-Host "└$("─" * $inner)┘"
    Write-Host ""
    Write-Host "Usage: ai <command>"
    Write-Host "Commands:"
    Write-Host ($cmd -f "install comfyui",        "Install or update ComfyUI")
    Write-Host ($cmd -f "install comfyui-manager","Install ComfyUI-Manager custom nodes")
    Write-Host ($cmd -f "install ollama",         "Install Ollama via winget")
    Write-Host ($cmd -f "install openwebui",      "Install Open Web UI for Ollama")
    Write-Host ($cmd -f "start <service>",        "Start a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "stop <service>",         "Stop a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "restart <service>",       "Restart a service (all, ollama, comfyui, openwebui)")
    Write-Host ($cmd -f "status [service]",       "System health or specific service status")
    Write-Host ($cmd -f "doctor",                 "Full system diagnostics (Git, Python, services, env)")
    Write-Host ($cmd -f "models list",            "List installed models")
    Write-Host ($cmd -f "clean cache",            "Delete all temporary files")
    Write-Host ($cmd -f "setup env",              "Check and fix environment variables")
    Write-Host ($cmd -f "setup path",             "Add AI_TOOLS to your PATH so 'ai' works from any path")
    Write-Host ($cmd -f "setup ports",            "Configure service ports")
    Write-Host ($cmd -f "help",                   "Show this message")
    Write-Host ""
}

function Get-PortConfig {
    $portFile = "${Root}\AI_CONFIG\ports.json"
    $defaults = @{ollama=11434; comfyui=8188; openwebui=8080}
    if (Test-Path $portFile) {
        $saved = Get-Content $portFile -Raw | ConvertFrom-Json
        $keys = @($defaults.Keys)  # snapshot to avoid modification-while-enumerating
        foreach ($key in $keys) {
            $val = $saved.$key
            if ($val -and $val -gt 0) { $defaults.$key = [int]$val }
        }
    }
    return $defaults
}

function Manage-ComfyUI {
    param([string]$Action)
    $ports = Get-PortConfig
    $launcher = "${Root}\AI_TOOLS\launch_comfyui.ps1"
    $comfyPort = $ports.comfyui
    $comfyRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${comfyPort} "

    switch ($Action) {
        "start" {
            if ($comfyRunning) {
                Write-Host "ComfyUI: Running on port $comfyPort"
                Write-Host "URL: http://127.0.0.1:$comfyPort"
                return
            }
            if (!(Test-Path $launcher)) {
                Write-Host "ComfyUI not installed. Run: ai install comfyui"
                exit 1
            }
            Write-Host "Starting ComfyUI..."
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
            Start-Sleep -Seconds 3
            Write-Host "ComfyUI started. URL: http://127.0.0.1:$comfyPort"
        }
        "stop" {
            if (-not $comfyRunning) {
                Write-Host "ComfyUI is not running."
                return
            }
            # Find PID listening on port 8188
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${comfyPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                Write-Host "ComfyUI stopped."
            } else {
                Write-Host "Could not find ComfyUI process."
            }
        }
        "status" {
            if ($comfyRunning) {
                Write-Host "ComfyUI: Running on port $comfyPort — http://127.0.0.1:$comfyPort"
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
    $ollamaRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${ollamaPort} "

    switch ($Action) {
        "start" {
            if ($ollamaRunning) {
                Write-Host "Ollama: Running on port $ollamaPort"
                Write-Host "API: http://localhost:$ollamaPort"
                return
            }
            Write-Host "Starting Ollama in background..."
            # Generate launcher if missing
            $ollamaLauncher = "${Root}\AI_TOOLS\launch_ollama.ps1"
            if (!(Test-Path $ollamaLauncher)) {
                "ollama serve" | Out-File $ollamaLauncher -Encoding utf8
            }
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ollamaLauncher`""
            Start-Sleep -Seconds 2
            Write-Host "Ollama started. API: http://localhost:$ollamaPort"
        }
        "stop" {
            if (-not $ollamaRunning) {
                Write-Host "Ollama is not running."
                return
            }
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${ollamaPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                Write-Host "Ollama stopped."
            } else {
                Write-Host "Could not find Ollama process."
            }
        }
        "status" {
            if ($ollamaRunning) {
                Write-Host "Ollama: Running on port $ollamaPort — http://localhost:$ollamaPort"
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
    $webuiRunning = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":${webuiPort} "

    switch ($Action) {
        "start" {
            if ($webuiRunning) {
                Write-Host "Open Web UI: Running on port $webuiPort"
                return
            }
            if (!(Test-Path $webuiPath)) {
                Write-Host "Open Web UI not installed. Run: ai install openwebui"
                exit 1
            }
            Write-Host "Starting Open Web UI..."
            Start-Process -WindowStyle Hidden -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$webuiLauncher`""
            Start-Sleep -Seconds 3
            Write-Host "Open Web UI started. URL: http://127.0.0.1:$webuiPort"
        }
        "stop" {
            if (-not $webuiRunning) {
                Write-Host "Open Web UI is not running."
                return
            }
            $line = netstat -ano | Select-String "LISTENING" | Select-String ":${webuiPort} "
            $procId = $line -replace '.*\s+(\d+)\s*$', '$1'
            if ($procId) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                Write-Host "Open Web UI stopped."
            } else {
                Write-Host "Could not find process for Open Web UI."
            }
        }
        "status" {
            if ($webuiRunning) {
                Write-Host "Open Web UI: Running on port $webuiPort — http://127.0.0.1:$webuiPort"
            } else {
                Write-Host "Open Web UI: not running"
            }
        }
    }
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

function Install-ComfyUI {
    Push-Location
    $ComfyPath = "$Root\AI_CORE\Apps\ComfyUI"
    $gpu = Get-GPUType

    Write-Host "Detected GPU: $gpu"

    if (!(Test-Path $ComfyPath)) {
        Write-Host "Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "$ComfyPath"
    } else {
        Write-Host "ComfyUI folder exists — pulling latest..."
        Set-Location "$ComfyPath"
        git pull
    }

    Set-Location "$ComfyPath"

    # Recreate venv if DirectML module is missing (AMD)
    $recreateVenv = $false
    if ((Test-Path ".\venv") -and $gpu -eq "amd") {
        $dmlCheck = & ".\venv\Scripts\python.exe" -c "import torch_directml; print('ok')" 2>$null
        if ($dmlCheck -ne "ok") {
            Write-Host "AMD GPU — DirectML backend not found, recreating venv"
            $recreateVenv = $true
        }
    }
    if ($recreateVenv -or !(Test-Path ".\venv")) {
        if ($recreateVenv) { Remove-Item -Recurse -Force ".\venv" }
        Write-Host "Creating Python 3.11 environment..."
        py -3.11 -m venv venv
    } else {
        Write-Host "Python environment exists — updating..."
    }

    .\venv\Scripts\Activate.ps1

    if ($gpu -eq "amd") {
        Write-Host "AMD GPU — installing DirectML stack..."
        pip install torch-directml 2>&1 | Out-Null
        pip install -r requirements.txt 2>&1 | Out-Null
        Write-Host "  Replacing CUDA torchaudio with CPU version..."
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
        Write-Host "  DirectML and CPU torchaudio ready"
    } else {
        pip install -r requirements.txt 2>&1 | Out-Null
    }

    deactivate

    # Update config with detected GPU
    $configPath = "$Root\AI_CONFIG\system_config.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json
        if ($config.gpu -eq "unknown" -and $gpu -ne "unknown") {
            $config.gpu = $gpu
            $config | ConvertTo-Json -Depth 10 | Out-File $configPath
            Write-Host "system_config.json updated: gpu=$gpu"
        }
    }

    # Extra model paths
    $yaml = @"
vault_config:
    checkpoints: $Root\AI_VAULT\models\diffusion\checkpoints
    loras: $Root\AI_VAULT\models\diffusion\loras
    vae: $Root\AI_VAULT\models\diffusion\vae
    controlnet: $Root\AI_VAULT\models\diffusion\controlnet
    embeddings: $Root\AI_VAULT\models\embeddings
"@
    $yaml | Out-File "$ComfyPath\extra_model_paths.yaml" -Encoding utf8

    # Quick validation
    Write-Host "Validating extra_model_paths.yaml..."
    $yamlLines = Get-Content "$ComfyPath\extra_model_paths.yaml"
    $firstLine = $yamlLines[0].Trim()
    if ($firstLine -match "^[a-zA-Z_]+:$" -and $yamlLines.Count -gt 1 -and $yamlLines[1] -match "^\s+[a-zA-Z_]+:") {
        Write-Host "  OK: named config block detected"
    } else {
        Write-Host "  WARNING: format may be wrong — dumping file:"
        $yamlLines | ForEach-Object { Write-Host "    >$_<" }
        Write-Host "  First line trimmed: '${firstLine}'"
        Write-Host "  Has indent check on line 2: $($yamlLines.Count -gt 1 -and $yamlLines[1] -match '^\s+[a-zA-Z_]+:')"
    }

    # Launcher with GPU flag
    $gpuFlag = if ($gpu -eq "amd") { " --directml" } else { "" }
    $launcher = @"
Set-Location "$ComfyPath"
.\venv\Scripts\Activate.ps1
python main.py --temp-directory "${Root}\AI_CACHE\comfyui_temp"$gpuFlag
"@
    # Ensure target directory exists
    $toolsDir = "${Root}\AI_TOOLS"
    if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }

    $launcher | Out-File "${Root}\AI_TOOLS\launch_comfyui.ps1" -Encoding utf8

    Write-Host ""
    Write-Host "ComfyUI ready ($gpu). Launch with: .\AI_TOOLS\launch_comfyui.ps1"
    Pop-Location
}

function Install-ComfyUI-Manager {
    Push-Location
    $nodeDir = "${Root}\AI_CORE\Apps\ComfyUI\custom_nodes\ComfyUI-Manager"
    if (!(Test-Path $nodeDir)) {
        Write-Host "Installing ComfyUI-Manager..."
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$nodeDir"
        Write-Host "ComfyUI-Manager installed. Restart ComfyUI to see it."
    } else {
        Write-Host "ComfyUI-Manager already installed — pulling updates..."
        Set-Location "$nodeDir"
        git pull
        Write-Host "Updated. Restart ComfyUI to see changes."
    }
    Pop-Location
}

function Install-Ollama {
    Write-Host "Installing Ollama..."
    winget install Ollama.Ollama --accept-source-agreements
    Write-Host "Done. Restart PowerShell, then set: setx OLLAMA_MODELS `"$Root\AI_CORE\_bindings\llm`""
}

function Install-OpenWebUI {
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

    Write-Host "Installing Open Web UI..."
    .\venv\Scripts\Activate.ps1
    pip install open-webui 2>&1 | Out-Null
    deactivate

    # Launcher that reads port from config
    $launcher = @"
`$webuiPath = "$webuiPath"
`$portFile = "`${webuiPath}\..\..\..\AI_CONFIG\ports.json"
`$port = 8080
if (Test-Path `$portFile) {
    `$cfg = Get-Content `$portFile | ConvertFrom-Json
    if (`$cfg.openwebui -and `$cfg.openwebui -gt 0) { `$port = `$cfg.openwebui }
}
Set-Location "`$webuiPath"
.\venv\Scripts\Activate.ps1
open-webui serve --port `$port
"@

    $toolsDir = "${Root}\AI_TOOLS"
    if (!(Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
    $launcher | Out-File "${Root}\AI_TOOLS\launch_openwebui.ps1" -Encoding utf8

    $defaultPort = (Get-PortConfig).openwebui
    Write-Host "Open Web UI installed."
    Write-Host "  Location: $webuiPath"
    Write-Host "  Launch: ${Root}\AI_TOOLS\launch_openwebui.ps1"
    Write-Host "  URL: http://127.0.0.1:$defaultPort"
    if ($defaultPort -ne 8080) {
        Write-Host "  Port set via AI_CONFIG\ports.json (default is 8080)"
    }
    Pop-Location
}

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
        $status = if ($installed -and $running) { "Up" } elseif ($installed) { "Stopped" } else { "──" }
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

    # GPU — name + total VRAM from WMI (always fast, registry-backed)
    $gpuUtil = $null
    $gpuVramUsed = $null
    $gpuVramTotal = $null
    $gpuName = $null

    $gpuInfo = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gpuInfo) {
        $gpuName = $gpuInfo.Name
        if ($gpuInfo.AdapterRAM -and $gpuInfo.AdapterRAM -gt 0) {
            $gpuVramTotal = [math]::Round($gpuInfo.AdapterRAM / 1GB, 1)
        }
    }

    # Probe utilization/VRAM via WDDM counters (fast on most systems, empty on some AMD)
    $gpuUtil = Get-Counter "\GPU(*)\Utilization Percentage" -ErrorAction SilentlyContinue | ForEach-Object { $_.CounterSamples } | Where-Object { $_.Path -notmatch "_Total|engine" } | Measure-Object -Property CookedValue -Average | Select-Object -ExpandProperty Average
    if (-not $gpuUtil -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        $gpuUtil = nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null
    }
    $gpuVramUsed = Get-Counter "\GPU Adapter Memory\Dedicated Usage" -ErrorAction SilentlyContinue | ForEach-Object { $_.CounterSamples } | Where-Object { $_.Path -notmatch "_Total" } | Measure-Object -Property CookedValue -Sum | Select-Object -ExpandProperty Sum

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
            if ($gpuVramTotal) { Write-Host "GPU:  $gpuName  ($gpuVramTotal GB)" }
            else { Write-Host "GPU:  $gpuName" }
        } else { Write-Host "GPU:  not detected" }
    }
    Write-Host ""

    # Models summary
    $llmDir = "$Root\AI_VAULT\models\llm"
    $diffDir = "$Root\AI_VAULT\models\diffusion"
    $embedDir = "$Root\AI_VAULT\models\embeddings"
    $ollamaRows = @(ollama list 2>$null | Select-Object -Skip 1)
    $ollamaModels = @($ollamaRows | ForEach-Object { $parts = $_ -split '\s{2,}'; if ($parts.Count -ge 1) { $parts[0] -replace ':latest','' } })
    $llmCount = $ollamaModels.Count
    $diffCount = if (Test-Path $diffDir) { @(Get-ChildItem $diffDir -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count } else { 0 }
    $vaeCount = if (Test-Path "$diffDir\vae") { @(Get-ChildItem "$diffDir\vae" -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count } else { 0 }
    Write-Host ""
    Write-Host "  Models:"
    Write-Host "    LLMs:        $llmCount"
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

function Show-Models {
    $llmDir = "$Root\AI_VAULT\models\llm"
    $diffDir = "$Root\AI_VAULT\models\diffusion"
    $embedDir = "$Root\AI_VAULT\models\embeddings"

    function List-Files($dir, $header, $pattern) {
        if (!(Test-Path $dir)) { return }
        $items = Get-ChildItem "$dir\*" -Include $pattern -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }
        if ($items.Count -eq 0) { return }
        Write-Host $header
        Write-Host "────────────────────────────────"
        foreach ($item in $items) {
            Write-Host "  $($item.BaseName)"
        }
        Write-Host ""
    }

    $rawModels = ollama list 2>$null | Select-Object -Skip 1
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
        $header = "│ " + "Model".PadRight($maxNameLen) + " │ " + "Size".PadRight($maxSizeLen) + " │"
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
    List-Files "$diffDir\checkpoints" "Diffusion (checkpoints)" @("*.safetensors","*.ckpt")
    List-Files "$diffDir\loras" "Diffusion (LoRAs)" @("*.safetensors")
    List-Files "$diffDir\vae" "VAE" @("*.safetensors","*.ckpt")
    List-Files "$diffDir\controlnet" "ControlNet" @("*.safetensors")
    List-Files $embedDir "Embeddings" @("*")

    if (!(Test-Path $llmDir) -and !(Test-Path $diffDir) -and !(Test-Path $embedDir)) {
        Write-Host "No models found."
    }
}

function Clean-Cache {
    $cacheDirs = @(
        "$Root\AI_CACHE\huggingface",
        "$Root\AI_CACHE\torch",
        "$Root\AI_CACHE\comfyui_temp",
        "$Root\AI_CACHE\ollama"
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

function Setup-Env {
    Write-Host "Checking environment variables..."
    Write-Host ""

    $vars = @(
        @{Name="OLLAMA_MODELS"; Expected="${Root}\AI_VAULT\models\llm"; Scope="User"; Help="Controls where Ollama stores models. Set before pulling."},
        @{Name="HF_HOME"; Expected="${Root}\AI_CACHE\huggingface"; Scope="User"; Help="Keeps Hugging Face downloads in AI_CACHE, not AI_VAULT."},
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

function Setup-Ports {
    $portFile = "${Root}\AI_CONFIG\ports.json"
    $defaults = @{ollama=11434; comfyui=8188; openwebui=8080}
    $current = @{}
    if (Test-Path $portFile) {
        $saved = Get-Content $portFile -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) { $current.$key = $saved.$key }
    }

    Write-Host "Service Port Configuration"
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

    if ($changed) {
        $current | ConvertTo-Json | Out-File $portFile -Encoding utf8
        Write-Host "Ports saved to $portFile"
        Write-Host "Restart services for changes to take effect."
    } else {
        Write-Host "No changes."
    }
}

function Doctor-Check {
    Write-Host "┌──────────────────────┬──────────────────────────────┐"

    $configPath = "$Root\AI_CONFIG\system_config.json"
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath | ConvertFrom-Json
        Write-Host ("│ {0,-20} │ {1,-28} │" -f "Stack", "v$($cfg.architecture_version) ($($cfg.gpu.ToUpper()))")
        Write-Host ("│ {0,-20} │ {1,-28} │" -f "Path", $Root)
    } else {
        Write-Host "│ not initialized      │ run 1-init.ps1"
        return
    }
    Write-Host "├──────────────────────┼──────────────────────────────┤"

    # Git
    $g = git --version 2>$null
    if ($g) { Write-Host ("│ {0,-20} │ {1,-28} │" -f "Git", ($g -replace '^git version ([\d.]+).*', '$1')) } else { Write-Host ("│ {0,-20} │ {1,-28} │" -f "Git", "FAIL") }

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
    if ($ff) { $ff = ($ff -split "`n")[0] -replace '^ffmpeg version ([\d.]+).*', '$1'; Write-Host ("│ {0,-20} │ {1,-28} │" -f "FFmpeg", $ff) } else { Write-Host ("│ {0,-20} │ {1,-28} │" -f "FFmpeg", "not found") }
    Write-Host "├──────────────────────┼──────────────────────────────┤"

    # Bindings
    $bindOk = $true
    foreach ($link in @("llm","diffusion","embeddings")) { if (!(Test-Path "$Root\AI_CORE\_bindings\$link")) { $bindOk = $false } }
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Model bindings", $(if ($bindOk) { "OK" } else { "MISSING" }))

    # Models
    $olMods = @(ollama list 2>$null | Select-Object -Skip 1)
    $diffC = @(Get-ChildItem "$Root\AI_VAULT\models\diffusion" -Recurse -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }).Count
    Write-Host ("│ {0,-20} │ {1,-28} │" -f "Models", "$($olMods.Count) LLM(s), $diffC diffusion")

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
            "comfyui"         { Install-ComfyUI }
            "comfyui-manager" { Install-ComfyUI-Manager }
            "ollama"          { Install-Ollama }
            "openwebui"       { Install-OpenWebUI }
            default           { Write-Host "Usage: ai install <comfyui|comfyui-manager|ollama|openwebui>" }
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
    "models"     {
        if ($SubCommand -eq "list") { Show-Models }
        else { Write-Host "Usage: ai models list" }
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
    "help"       { Show-Help }
    default      { Show-Help }
}
