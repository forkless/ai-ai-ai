import os
os.environ["HF_HOME"] = "/home/pe1085/development/ai-ai-ai/tests/HF_HOME"
from huggingface_hub import snapshot_download

models = [
    "hf-internal-testing/tiny-random-bert",
    "hf-internal-testing/tiny-random-gpt2",
    "hf-internal-testing/tiny-random-roberta",
]
for model in models:
    print(f"Downloading {model}...")
    path = snapshot_download(model)
    print(f"  -> {path}")
