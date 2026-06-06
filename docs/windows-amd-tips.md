# Windows AMD GPU Tips

## ROCm Setup

### Requirements

- AMD Radeon RX 7000 series or newer
- AMD driver **26.2.2+**
- Windows 10 or 11
- Python 3.12 (installed by `2-deps.ps1`)

### Quick Install

```powershell
.\scripts\2-deps.ps1          # install Python 3.12 + other deps
.\scripts\3-comfyui.ps1 -Backend rocm
```

Or via the CLI after bootstrap:

```powershell
ai install comfyui -Backend rocm
```

### Verifying ROCm is Working

```powershell
ai doctor
# Look for "ROCm: avail"

# Or check directly:
.\venv_rocm\Scripts\python.exe -c "import torch; print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0)); print(torch.version.hip)"
```

Expected output:
```
True
AMD Radeon RX 9070 XT
7.2.53211-158bd99533
```

### Switching Backends

```powershell
ai install comfyui -Backend directml   # switch to DirectML
ai install comfyui -Backend rocm       # switch back to ROCm
```

Both venvs coexist — `venv` (DirectML, Python 3.11) and `venv_rocm` (ROCm, Python 3.12).

---

## Troubleshooting

### Keep ComfyUI Updated

ComfyUI has a rapid release cycle — often multiple updates per week. Running
`ai install comfyui` (or `ai install all`) regularly pulls the latest version
and updates dependencies. Many issues resolve with an update.

### ComfyUI starts but `cuda:0` is not available

```powershell
# Verify PyTorch detects the GPU
.\venv_rocm\Scripts\python.exe -c "import torch; print(torch.cuda.is_available())"
```

If `False`, the ROCm wheels didn't install correctly. Reinstall with:

```powershell
ai install comfyui -Backend rocm
```

### `onnxruntime` missing for custom nodes

```powershell
.\venv_rocm\Scripts\python.exe -m pip install onnxruntime
```

### `insightface` module not found

Download a `cp312`-compatible wheel and install:

```powershell
.\venv_rocm\Scripts\python.exe -m pip install insightface-0.7.3-cp312-cp312-win_amd64.whl
```

### `MIOPEN_FIND_MODE=2` slows text encoders

MIOPEN_FIND_MODE=2 skips kernel benchmarking which speeds initial inference but
can degrade CLIP/text-encoder performance. Remove the env var or set it to `1`.

### torchaudio ImportError / CUDA DLL crash

This only affects the **DirectML** path, not ROCm. If you see CUDA DLL errors on
an AMD card, you're running the DirectML `venv` with a PyPI torchaudio that
bundles CUDA binaries. The scripts handle this automatically during DirectML
install by patching torchaudio.

---

## Default Launch Flags

Current defaults set by the launcher:

```
--use-pytorch-cross-attention --disable-smart-memory --bf16-unet
--output-directory D:\AI\AI_WORKSPACE\output
--temp-directory D:\AI\AI_CACHE\comfyui_temp
```

These are tuned for ROCm stability. See `docs/comfyui-tuning.md` for details.

---

## Known Limitations

| Issue | Details |
|-------|---------|
| **ROCm on Windows** | AMD's ROCm Windows support is newer than Linux. Expect fewer community resources. |
| **Python 3.12 only** | ROCm PyTorch wheels are cp312-only. The DirectML path uses Python 3.11. |
| **HIP SDK via pip** | ROCm SDK is installed as Python wheels, not a system installer. |
