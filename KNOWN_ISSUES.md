# Known Issues

## ComfyUI-Manager V4 migration

**Status:** To be addressed

**Issue:** ComfyUI-Manager V4 may ship as a pip-managed component integrated via
`--enable-manager` flag, replacing the current custom_nodes git clone approach.

Our scripts clone Manager into `custom_nodes/ComfyUI-Manager/` via git. If a
future ComfyUI version ships Manager as a built-in, the clone method will
conflict or be redundant.

**Fix:** Detect ComfyUI version during install. For versions that support the new
method, use `--enable-manager` instead of git clone. Fall back to git clone for
older versions.

**Trigger:** When ComfyUI releases a version where the V4 Manager is standard and
the git clone approach breaks or causes warnings.

### How to check if you're affected

1. Load a workflow saved in API format
2. See error: `e.inputs?.map is not a function`
3. Error points to `components-manager.js`

→ You're on Manager V3 with a newer ComfyUI core.

---

## AMD Driver Stability: 26.5.x / 26.6.1 vs 26.3.1 (RX 9070 series)

**Status:** Upstream issue — not fixable by scripts

**Summary:** Adrenalin 26.5.x and 26.6.1 drivers exhibit system-wide instability on
RX 9070 series cards. 26.3.1 remains the recommended stable version for AI workloads,
gaming, and daily desktop use.

### Stability Comparison

| Use Case | 26.3.1 | 26.5.x / 26.6.1 |
|----------|--------|------------------|
| ROCm Detection | ✅ Detected and working | ✅ Detected and working |
| AI/Compute Stability | ✅ Rock solid (12+ hour FLUX runs) | ⚠️ Functional but system-wide instability affects long runs |
| Daily Desktop | ✅ Rock solid | ❌ Freezes during basic tasks (Chrome video, multi-monitor) |
| Heavy Gaming (UE5) | ✅ Stable | ❌ DX12 device removed errors, long freeze frames, potential crashes |
| Overall System Stability | ✅ Rock solid | ❌ Unstable — freezes occur even without AI workloads |

### Key Insight

The newer drivers detect and support ROCm — the compute stack is present and
functional. However, the display driver / WDDM layer is fundamentally unstable,
causing system-wide freezes during basic desktop tasks and gaming, even when no
AI workloads are running. This makes them unsuitable for daily driving despite
ROCm support.

### Known Issues on 26.5.x / 26.6.1

- **Desktop & Display Driver:** System freezes during simple tasks (YouTube in
  Chrome, multi-monitor use) even without AI workloads running.
- **Heavy Gaming (UE5 / DX12):** Persistent DX12 device removed errors and
  library crashes (kernel32/ntdll). Stability issues began after AMD implemented
  changes for RDNA 4 (RX 9000 series) support, affecting RX 7000/9000 cards.
- **Ray Tracing:** On RX 9070 series in UE4 games, ray tracing causes full-screen
  freezes lasting several seconds — not yet acknowledged in driver known issues.
- **Blender Cycles:** 26.5.1 has HIP issues due to ROCm runtime change. AMD
  developer confirmed the driver no longer ships the ROCm 6 runtime used by
  current Cycles builds.

### Recommendation

**Stay on Adrenalin 26.3.1** for a stable system that handles AI/Compute, daily
desktop, and gaming. The newer drivers work with ROCm but the display driver
layer is too unstable for daily use.
