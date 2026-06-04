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

## Registry: `AI_CONFIG/model_registry.json`

A local index of all known models. Created as an empty placeholder by `1-init.ps1`.

### Schema

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

## Future: Automated Model Management

Beyond manual promote, the architecture supports:

- **`ai install <model>`** — download to cache, auto-promote to vault, register, wire into bindings
- **`ai remove <model>`** — unregister + optionally delete from vault
- **`ai list --cached`** — show models in cache that haven't been promoted yet
- **`ai sync registry`** — scan vault for unregistered models, add them
