# Ai, ai, ai! Bootstrap v1.1

Provision a structured local AI workstation on Windows in three scripts. Models,
runtimes, config, workspace, tools, and caches each get their own layer — no
duplication, safe reinstalls, no lost models.

```
D:\AI\
├── AI_CONFIG\     settings, model registry, port config
├── AI_CORE\       runtimes (ComfyUI, Ollama, Open Web UI)
├── AI_VAULT\      permanent models (single source of truth)
├── AI_WORKSPACE\  input, output, workflows
├── AI_TOOLS\      helper scripts, launchers, utilities
└── AI_CACHE\      temp data (safe to delete anytime)
```

Core principle: **models live once in the vault.** Every runtime consumes them
through a symlink binding layer. Reinstall any tool without touching your data.

## Requirements

- Windows 10 or 11
- PowerShell 5+
- Administrator rights (for `2-deps.ps1`)

## Quick Start

```powershell
# Allow local scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Unblock downloaded files (if downloaded from the web)
Get-ChildItem *.ps1 | Unblock-File

# Step 1 — create folders, symlinks, config
.\scripts\1-init.ps1

# Restart PowerShell

# Step 2 — install Git, Python, Ollama, FFmpeg
.\scripts\2-deps.ps1

# Restart PowerShell

# Step 3 — install ComfyUI (clone, venv, model paths, launcher)
.\scripts\3-comfyui.ps1

# Make the ai command available everywhere
.\scripts\ai.ps1 setup path
```

## Daily Use

| Command | What it does |
|---------|-------------|
| `ai start all` | Start all services |
| `ai stop all` | Stop all services |
| `ai restart all` | Restart all services |
| `ai status` | Dashboard — running services, ports, model counts |
| `ai doctor` | Full system diagnostics |
| `ai list` | List installed models by category |
| `ai install all` | Install or update everything |
| `ai install <service>` | Install or update comfyui, comfyui-manager, ollama, openwebui |
| `ai watch <service>` | Live-tail service logs (comfyui, ollama, openwebui) |
| `ai setup ports` | Change service ports |
| `ai setup env` | Check and fix environment variables |
| `ai clean cache` | Free up temporary disk space (includes archived logs) |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/1-init.ps1` | Creates folder structure, detects GPU, sets up symlinks, writes config files |
| `scripts/2-deps.ps1` | Installs Git, Python 3.10/3.11, Ollama, FFmpeg via winget. Sets environment variables |
| `scripts/3-comfyui.ps1` | Clones ComfyUI, creates Python 3.11 venv, installs dependencies (CUDA or DirectML), configures model paths |
| `scripts/ai.ps1` | Daily driver CLI — service management, status, diagnostics, model listing, cache cleanup, environment setup |

## GPU Support

The scripts detect your GPU and install the correct backend automatically:

- **NVIDIA** — CUDA (via standard torch)
- **AMD** — DirectML (torch-directml) with a torchaudio workaround to avoid CUDA DLL crashes

## Port Configuration

| Service | Default Port |
|---------|-------------|
| Ollama | 11434 |
| ComfyUI | 8188 |
| Open Web UI | 3000 |

Change with `ai setup ports`. Settings persist in `AI_CONFIG\ports.json`.

## Environment Variables

The scripts redirect download caches away from the vault:

| Variable | Points To | Purpose |
|----------|-----------|---------|
| `OLLAMA_MODELS` | `AI_VAULT\models\llm` | Ollama model storage |
| `HF_HOME` | `AI_CACHE\huggingface` | Hugging Face downloads |
| `TORCH_HOME` | `AI_CACHE\torch` | PyTorch cache |

Check and fix with `ai setup env`.

## Architecture

The 6-layer structure separates configuration, runtimes, assets, workspace,
tools, and caches into independent layers:

```
AI_CONFIG\     — centralized configuration and model registry
AI_CORE\       — AI runtimes and applications
AI_VAULT\      — permanent models (LLMs, diffusion, embeddings, CLIP)
AI_WORKSPACE\  — user files (input, output, workflows)
AI_TOOLS\      — helper scripts and utilities
AI_CACHE\      — temporary downloads, caches, and logs (safe to delete)
```

A symlink binding layer at `AI_CORE\_bindings` routes model requests from
runtimes to `AI_VAULT\models\`, keeping the vault as the single source of truth.

## Documentation

- [Bootstrap scripts guide](https://forkless.github.io/knowledge-base/setup/bootstrap-scripts.html)
- [AI Control Panel reference](https://forkless.github.io/knowledge-base/setup/ai-control-panel.html)
- [Folder architecture rationale](https://forkless.github.io/knowledge-base/setup/organize-your-ai-folders.html)
- [FAQ / troubleshooting](https://forkless.github.io/knowledge-base/faq.html)

## License

MIT
