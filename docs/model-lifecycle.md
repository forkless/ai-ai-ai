# Model Lifecycle & Registry

## Overview

Models pass through three layers with distinct semantics:

```
AI_CACHE  (staging)  ──promote──▶  AI_VAULT  (canonical)  ──serve──▶  AI_CORE / bindings
```

Each layer has a clear purpose. Cache is rebuildable. Vault is permanent. Bindings are runtime.

## Layer Definitions

### AI_CACHE — Staging / Runtime Cache

```
AI_CACHE/
├── huggingface/    HF_HOME — Hugging Face snapshot cache
├── torch/          TORCH_HOME — PyTorch hub downloads
└── comfyui_temp/   ComfyUI runtime temp files
```

- **Semantics:** Transient build artifact. Safe to delete. Rebuilds on demand.
- **Format:** Framework-native (HF blob/snapshot/ref structure, PyTorch hub layout).
- **Contents:** Everything a framework downloads automatically. Not curated.
- **Lifecycle:** Cleaned by `ai clean cache`. Individual models can be promoted to vault.

### AI_VAULT — Canonical Model Storage

```
AI_VAULT/
├── models/
│   ├── llm/
│   │   └── my-model/
│   │       ├── model.safetensors
│   │       ├── config.json
│   │       └── tokenizer.json
│   ├── diffusion/     (checkpoints, loras, vae, etc.)
│   └── embeddings/
├── datasets/
└── .cache/huggingface/   (HF_HOME — preserved by clean cache)
```

- **Semantics:** Permanent, curated, source of truth.
- **Format:** Normalized — clean directory per model, framework-agnostic.
- **Contents:** Only models explicitly promoted or manually placed.
- **Lifecycle:** Never touched by `ai clean cache`. Removed manually.

### AI_CORE / _bindings — Model Routing

```
AI_CORE/_bindings/
├── llm/         → symlink junction → AI_VAULT/models/llm/
├── diffusion/   → symlink junction → AI_VAULT/models/diffusion/
└── embeddings/  → symlink junction → AI_VAULT/models/embeddings/
```

Runtimes (ComfyUI, Ollama, Open Web UI) resolve models through `extra_model_paths.yaml` which points to `AI_VAULT/models/` via the bindings layer. They never reference the cache directly.

## Promotion: Cache → Vault

Promotion materializes a clean copy of a model from cache into the vault.

### What it does

1. **Resolve snapshot** — pick `snapshots/<sha>/` from the HF cache entry
2. **Resolve symlinks** — follow all symlinks to their blob targets, read the content
3. **Normalize layout** — write a clean model directory under `AI_VAULT/models/<category>/<name>/`
4. **Register** — add an entry to `AI_CONFIG/model_registry.json`

### Input

```
AI_CACHE/huggingface/hub/models--hf-internal-testing--tiny-random-bert/snapshots/f171d7ba.../
    config.json          → symlink → ../../blobs/<hash>
    model.safetensors    → symlink → ../../blobs/<hash>
    tokenizer.json       → symlink → ../../blobs/<hash>
    ...
```

### Output

```
AI_VAULT/models/llm/tiny-random-bert/
    model.safetensors   (real file, resolved from blob)
    config.json         (real file, resolved from blob)
    tokenizer.json      (real file, resolved from blob)

AI_CONFIG/model_registry.json  (updated)
```

### Trade-offs

| Pro | Con |
|-----|-----|
| Vault is framework-agnostic — works with any runtime | Duplicates disk usage (cache copy + vault copy) |
| Cache can be wiped safely after promotion | Needs a materialization step (time + I/O) |
| Vault format is stable and portable | Doesn't preserve HF snapshot history |
| Clean bindings — ComfyUI/Ollama resolve directly | Manual trigger — not automatic |

## What Registration Is

Registration is not storage and not duplication.

It is a **mapping layer**:

| Maps | Example |
|------|---------|
| model name → physical location | `llm:my-fat-model` → `AI_VAULT/models/llm/my-fat-model` |
| model type → runtime handler | `llm` → Ollama, `diffusion` → ComfyUI |
| metadata → version, source, quantization | `"source": "huggingface/meta-llama/Llama-3-8B"` |

Registering a model means writing its canonical identity into `AI_CONFIG/model_registry.json` so `AI_CORE` can resolve it to a path in `AI_VAULT`. The weights stay on disk — only the pointer and metadata are added.

### Necessity

Without a registry, every tool has its own source of truth:

- ComfyUI scans folders blindly
- Ollama maintains its own model list
- LM Studio uses its own index

Three conflicting sources of truth. With a registry, `AI_CONFIG/model_registry.json` becomes the single authoritative index.

### Architectural Roles

```
AI_VAULT     → Storage         (files on disk)
AI_CONFIG    → Identity/Truth  (model_registry.json)
AI_CORE      → Runtime Resolver (bindings + routing)
```

Each layer has a single responsibility. The vault holds the bytes. Config declares existence. Core serves them.

### The Full Promote Pipeline

When you promote a model:

1. **Materialize** — resolve the HF snapshot into a clean directory under `AI_VAULT/models/<category>/<name>/`
2. **Register** — write an entry into `AI_CONFIG/model_registry.json` (name, path, source, format, revision, pinned)
3. **Route** — `AI_CORE/_bindings` uses the registry to enumerate available models and expose them to runtimes

## Registry: `AI_CONFIG/model_registry.json`

A local index of all known models. Created as an empty placeholder by `1-init.ps1`.

### Schema

Key-based format (preferred — direct lookup by `type:name`):

```json
{
  "version": 1,
  "models": {
    "llm:my-fat-model": {
      "name": "my-fat-model",
      "category": "llm",
      "path": "AI_VAULT/models/llm/my-fat-model",
      "type": "llm",
      "format": "safetensors",
      "source": "huggingface/meta-llama/Llama-3-8B",
      "version": "3.1",
      "pinned": true
    }
  }
}
```

Or array-based format for sequential iteration:

```json
{
  "version": 1,
  "models": [
    {
      "name": "tiny-random-bert",
      "category": "llm",
      "source": "huggingface",
      "source_id": "hf-internal-testing/tiny-random-bert",
      "revision": "f171d7baecaf37b5da5a3616d8833b9969753535",
      "path": "D:\\AI\\AI_VAULT\\models\\llm\\tiny-random-bert",
      "format": "safetensors",
      "size_bytes": 12345678,
      "pinned": true,
      "promoted_at": "2026-06-04T23:30:00Z"
    },
    {
      "name": "sd-xl-base-1.0",
      "category": "diffusion",
      "source": "manual",
      "source_id": null,
      "revision": null,
      "path": "D:\\AI\\AI_VAULT\\models\\diffusion\\checkpoints\\sd_xl_base_1.0",
      "format": "safetensors",
      "size_bytes": 6987654321,
      "pinned": true,
      "promoted_at": null
    }
  ]
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Short display name |
| `category` | yes | `llm`, `diffusion`, `embeddings` |
| `source` | yes | `huggingface`, `manual`, `ollama`, `converter` |
| `source_id` | no | Upstream identifier (HF repo ID, URL, etc.) |
| `revision` | no | Source revision / commit SHA |
| `path` | yes | Absolute path to the model directory in the vault |
| `format` | yes | `safetensors`, `gguf`, `pytorch`, `onnx` |
| `size_bytes` | yes | Total size on disk |
| `pinned` | yes | Whether `ai clean cache` should skip this |
| `promoted_at` | no | ISO timestamp of promotion (null if manually placed) |

### Usage in `ai list`

The registry replaces the current vault-scan approach. Instead of walking directories recursively, `ai list` reads the registry and displays models grouped by category. This is faster and more reliable.

### Usage in `clean cache`

`Clean-Cache` consults the registry before deleting cache entries. Any model with `pinned: true` is skipped. Models not in the registry are fair game.

## Open Questions

1. **Promote trigger** — manual (`ai promote <model>`) or automatic (post-HF-download hook)?
2. **Multiple formats** — HF cache often stores both `pytorch_model.bin` and `model.safetensors`. Which to vault?
3. **Demote / unregister** — remove from registry + optionally re-download to cache?
4. **Ollama integration** — Ollama pulls go to `AI_VAULT/models/llm/` via `OLLAMA_MODELS`. Should those auto-register?
5. **ComfyUI model discovery** — ComfyUI's model folders under the vault aren't in the registry today. Should `ai doctor` / `ai list` detect unregistered vault models and offer to index them?

## Model Resolution Pipeline

The registry is a static index. The resolver is the runtime that uses it to pick the right file.

### The Problem

A single model name is no longer enough. A model may have:

- **Multiple formats:** `safetensors`, `gguf`, `pytorch`
- **Multiple quantizations:** `fp16`, `int8`, `q4`
- **Multiple runtimes:** Ollama needs GGUF, Transformers needs safetensors, ComfyUI needs diffusion format
- **Hardware constraints:** GPU with 12GB VRAM vs 24GB vs CPU-only

Given a request, AI_CORE must decide exactly which file to load.

### Resolution Pipeline

```
request → registry → candidate set → scoring → final artifact path
```

### Step 1: Registry with Variants

The registry schema expands to include variants per model:

```json
{
  "llm:my-model": {
    "base_path": "AI_VAULT/models/llm/my-model",
    "variants": [
      {
        "id": "fp16",
        "format": "safetensors",
        "quant": "fp16",
        "device": "gpu",
        "priority": 10
      },
      {
        "id": "int8",
        "format": "safetensors",
        "quant": "int8",
        "device": "cpu",
        "priority": 5
      },
      {
        "id": "gguf-q4",
        "format": "gguf",
        "quant": "q4",
        "runtime": "llama.cpp",
        "priority": 8
      }
    ]
  }
}
```

The registry is no longer a path list — it is a **decision graph**.

### Step 2: Runtime Context

When a model is requested, AI_CORE knows the current context:

```json
{
  "device": "gpu",
  "vram_gb": 12,
  "runtime": "transformers",
  "latency": "balanced"
}
```

### Step 3: Scoring Function

Each variant receives a score based on how well it matches the runtime context:

```
score =
  + device_match      (GPU variant on GPU system: +3)
  + format_match      (format compatible with runtime: +2)
  + quant_preference  (higher precision: +3, efficient: +3)
  + explicit_priority (registry priority field)
  - penalties         (VRAM overflow: -10, runtime mismatch: -5)
```

Example:

| Variant | GPU match | Quality | Efficiency | Runtime | Score |
|---------|-----------|---------|------------|---------|-------|
| fp16    | +3        | +3      | 0          | +2      | **8** |
| int8    | +3        | +1      | +3         | +2      | **9** |
| gguf    | 0         | 0       | +3         | -5      | **-2** |

Int8 wins — efficient GPU variant with acceptable quality.

### Step 4: Selection

```
selected = argmax(variants, score)
```

Tiebreaker: higher precision, then higher registry priority.

### Step 5: Resolution Output

```json
{
  "model": "llm:my-model",
  "selected_variant": "int8",
  "path": "AI_VAULT/models/llm/my-model/int8/",
  "runtime": "transformers"
}
```

### Step 6: Binding Layer Abstraction

With the resolver in place, `_bindings` becomes a function call, not a symlink:

```
AI_CORE/_bindings/llm → model_resolver("llm:my-model")
```

Apps never see disk paths. They request by model name only.

### What This Enables

| Capability | How |
|------------|-----|
| **Automatic hardware adaptation** | Same model, different machine → different variant selected |
| **Multi-runtime support** | Ollama → GGUF, Transformers → safetensors, ComfyUI → diffusion |
| **Graceful fallback** | fp16 fails → auto fallback to int8 |
| **Clean upgrades** | Add fp8, new quantizations without changing app code |

### Architectural Analogy

| Concept | Analogy |
|---------|---------|
| AI_VAULT | Binary object files |
| Registry | Symbol table |
| Resolver | Linker |
| Variants | Build targets |
| AI_CACHE | Source/build artifacts (never participates in final selection) |

### Final Mental Model

```
REQUEST (llm:my-model)
  ↓
AI_CORE resolver
  ↓
AI_CONFIG (registry + variants)
  ↓
scoring engine (runtime context × variant properties)
  ↓
AI_VAULT (final artifact path)
  ↓
runtime execution
```

You are no longer picking a model file. You are resolving the best execution target for a model under current constraints.

## Future: Automated Model Management

Beyond manual promote, the architecture supports:

- **`ai install <model>`** — download to cache, auto-promote to vault, register, wire into bindings
- **`ai remove <model>`** — unregister + optionally delete from vault
- **`ai list --cached`** — show models in cache that haven't been promoted yet
- **`ai sync registry`** — scan vault for unregistered models, add them
