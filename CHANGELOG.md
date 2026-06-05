# Changelog

## 2026-06-05

### ROCm backend
- **ROCm ComfyUI backend** — AMD-native PyTorch via ROCm 7.2.1 on Python 3.12 (`venv_rocm`), coexists with existing DirectML `venv`
- **Dual-backend install** — `ai install comfyui -Backend rocm|directml`. Reads existing backend from config on reinstall, no re-prompt
- **Launcher auto-selects venv** — `Manage-ComfyUI` reads `comfyui_backend` from `system_config.json`, activates correct venv, sets `--directml` only when needed
- **Doctor ROCm check** — `ai doctor` shows ROCm availability when `venv_rocm` is present
- **Default launch flags** — `--use-pytorch-cross-attention --disable-smart-memory --bf16-unet --output-directory AI_WORKSPACE\output`
- **Python 3.12** — added to `2-deps.ps1` for the ROCm stack

### Startup reliability
- **Silent start** — `ai start`, `ai stop`, `ai restart` are now quiet on success; errors dump the log tail and exit with code 1
- **Post-launch verification** — all three `Manage-*` "start" actions verify the port is listening after the sleep wait; failure shows last 15 lines of the service log
- **Log rotation per start** — `Rotate-LogFile` now archives the log file on every `ai start`, not just cross-day. Each session gets a clean log for accurate error diagnosis
- **Open Web UI wait increased** — sleep bumped from 3 to 5 seconds to allow Alembic migrations

### Bugs
- **Install-ComfyUI launcher port** — was hardcoded to `8188` regardless of `ports.json` config; now reads from `Get-PortConfig`
- **Install-ComfyUI launcher listen address** — was hardcoded to `0.0.0.0`; now reads from `Get-PortConfig`

## 2026-06-04

### Ports
- **Open Web UI default port changed from 8080 to 3000** — updated in `1-init.ps1`, `ai.ps1` (Get-PortConfig, Manage-WebUI, Install-OpenWebUI, Setup-Ports), and README.

### Vault layout
- Added `diffusion_models/` and `clip/` directories to vault structure (`1-init.ps1`)
- Mapped both paths in `extra_model_paths.yaml` (`3-comfyui.ps1`, `ai.ps1` Install-ComfyUI)
- Install functions now ensure vault directories exist before writing model path config

### Install safety
- **Services are stopped before install** — all four install functions (ComfyUI, ComfyUI-Manager, Ollama, OpenWebUI) now call their respective Manage-X `"stop"` before proceeding
- **Wait for process exit after stop** — each `"stop"` action polls for PID disappearance up to 10 seconds before returning
- **Fail on stop failure** — if a process can't be stopped within the 10-second timeout, the script exits with an error message instead of proceeding

### Diagnostics
- **Fixed version extraction** — Git and FFmpeg version strings with a trailing period (e.g. `2.54.0.`) are now correctly stripped to `2.54.0` (`ai.ps1` Doctor-Check)

### Logging
- **Service output redirected to files** — all three services now write stdout+stderr to `AI_CACHE\logs\<service>.log` instead of discarding output
- **`ai watch <service>`** — new command for live-tail viewing logs via `Get-Content -Wait` (replaces earlier `ai tail`)
- **Log rotation** — on service start, logs from previous days are zipped to `AI_CACHE\logs\archive\<service>_YYYYMMDD.zip`; archives older than 7 days are cleaned up

### CLI improvements
- **`ai install all`** — single command to install/update all four apps in sequence
- **`ai install <service>`** — unified help entry covering all installable apps
- **Consistent help notation** — all commands use `<service>` parameter notation; removed redundant entries and `Commands:` label
- **`ai watch`** — renamed from `ai tail`

### Cache policy
- **HF_HOME restored to AI_CACHE clean list** — framework cache is cleanable. Added warning to pin models to AI_VAULT before running clean cache.
- **Removed dead `AI_CACHE\ollama` directory** — nothing writes there; Ollama models go to `AI_VAULT\models\llm` via `OLLAMA_MODELS`. Removed from `1-init.ps1` folder creation and `Clean-Cache`.

### Documentation
- Updated README daily-use table, vault layout description, cache folder description
- Added inline function and section doc comments to all scripts (`32a68bf`)
