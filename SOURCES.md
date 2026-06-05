# Software Inventory & Sources

Every external software package installed by the bootstrap scripts, listed
with its source location for transparency.

## System Dependencies (winget)

| Software | Source | Installer |
|----------|--------|-----------|
| **Git** | `winget install Git.Git` | Microsoft Store / winget |
| **Python 3.10** | `winget install Python.Python.3.10` | Microsoft Store / winget |
| **Python 3.11** | `winget install Python.Python.3.11` | Microsoft Store / winget |
| **Python 3.12** | `winget install Python.Python.3.12` | Microsoft Store / winget |
| **Ollama** | `winget install Ollama.Ollama` | Microsoft Store / winget |
| **FFmpeg** | `winget install FFmpeg` | Microsoft Store / winget |

## Applications

| Software | Source | Method |
|----------|--------|--------|
| **ComfyUI** | `https://github.com/comfyanonymous/ComfyUI.git` | git clone |
| **ComfyUI-Manager** | `https://github.com/ltdrdata/ComfyUI-Manager.git` | git clone |
| **Open Web UI** | `pip install open-webui` | PyPI |

## ComfyUI Python Dependencies

| Package | Source | Notes |
|---------|--------|-------|
| **ComfyUI requirements.txt** | PyPI (`pip install -r requirements.txt`) | Standard PyPI packages; includes various ML/diffusion libraries |
| **torch-directml** | PyPI (`pip install torch-directml`) | AMD DirectML backend; replaces CUDA torch with CPU torch |

## AMD ROCm Stack (pip from repo.radeon.com)

All hosted at `https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/`

| Package | Wheel |
|---------|-------|
| **ROCm SDK Core** | `rocm_sdk_core-7.2.1-py3-none-win_amd64.whl` |
| **ROCm SDK Devel** | `rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl` |
| **ROCm SDK Libraries Custom** | `rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl` |
| **ROCm 7.2.1** | `rocm-7.2.1.tar.gz` |
| **torch 2.9.1+rocm7.2.1** | `torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl` |
| **torchaudio 2.9.1+rocm7.2.1** | `torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl` |
| **torchvision 0.24.1+rocm7.2.1** | `torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl` |

## AMD DirectML Patches

| Package | Source | Notes |
|---------|--------|-------|
| **torchaudio (patched)** | `https://download.pytorch.org/whl/cpu` | CPU-only torchaudio replaces PyPI version to avoid CUDA DLL crashes on AMD |


