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
