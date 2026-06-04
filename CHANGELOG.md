# Changelog

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

### Documentation
- Updated README daily-use table, vault layout description, cache folder description
- Added inline function and section doc comments to all scripts (`32a68bf`)
