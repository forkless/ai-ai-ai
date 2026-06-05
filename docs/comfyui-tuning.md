# ComfyUI Tuning & Launch Options

## Environment Variables

### MIOPEN_FIND_MODE

Sets MIOpen kernel discovery mode. Affects AMD ROCm GPUs only.

| Value | Behavior |
|-------|----------|
| `1` (default) | Benchmark on every launch — finds optimal kernels for the hardware |
| `2` | Use cached kernel solutions — skips benchmarking, faster startup |

**Trade-off:** `MIOPEN_FIND_MODE=2` speeds up initial inference by skipping kernel
benchmarking, but can degrade CLIP/text-encoder performance significantly on some
models. If text encoding feels sluggish, revert to the default (unset or `1`).

**Usage:**

```powershell
$env:MIOPEN_FIND_MODE = "2"
python main.py --listen 0.0.0.0 --port 8188 --output-directory D:\AI\AI_WORKSPACE\output ...
```

Or set it in the launch script before the `python` line.

---

## CLI Flags

| Flag | Purpose |
|------|---------|
| `--use-pytorch-cross-attention` | Use PyTorch native cross-attention (default in launcher) |
| `--disable-smart-memory` | Disable ComfyUI smart memory management (default in launcher) |
| `--bf16-unet` | Run UNet in bfloat16 precision on ROCm (default in launcher) |
| `--reserve-vram <GB>` | Reserve VRAM for system/other GPU tasks (e.g., `1.2` = 1.2 GB) |
| `--force-fp32` | Force float32 computation; avoids fp16 precision issues on some AMD cards |
| `--output-directory <path>` | Save generated images to a custom directory |
| `--temp-directory <path>` | Set temporary file directory |
