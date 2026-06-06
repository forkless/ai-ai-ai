# Compatibility

## ROCm vs DirectML

| Feature | ROCm Path (Native) | DirectML Path (Fallback) |
|---------|-------------------|--------------------------|
| **Hardware Support** | RDNA3 & RDNA4 only (RX 6000, 7000, 9000) | All RDNA1–4 (RX 5000, 6000, 7000, 9000) |
| **Python Version** | 3.12 | 3.11 |
| **Performance** | Native ROCm — faster | DirectML translation layer — slower |
| **Driver Requirement** | AMD driver 26.2.2+ | Any AMD driver |

### RX 5000 Series

The DirectML path supports RX 5000 series (RDNA1). ROCm does not support RDNA1
hardware — only RDNA3 (RX 7000) and RDNA4 (RX 9000) have official ROCm support
on Windows.

## GPU Detection Logic

The scripts detect your GPU via WMI and select the appropriate backend:

1. **NVIDIA** → CUDA (no backend choice)
2. **AMD RDNA3/RDNA4** → Prompts for ROCm or DirectML
3. **AMD RDNA1/RDNA2** → DirectML only (ROCm unavailable)

## Operating System

| OS | Support |
|----|---------|
| Windows 10 | ✅ Supported |
| Windows 11 | ✅ Supported |
| Linux | ❌ Not supported (scripts are PowerShell-based) |
