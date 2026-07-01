# 128 GB Unified Memory — Budget

GB10 teilt **einen** kohärenten 128-GB-Pool zwischen CPU und GPU. Alle Dienste
konkurrieren darum → Kern klein halten, Rest on-demand.

## Beispiel-Budget (Richtwerte, quant-abhängig)
| Dienst                        | Modus      | ~Speicher |
|-------------------------------|------------|-----------|
| OS + DGX-Overhead             | –          | ~10 GB    |
| Qdrant + LiteLLM              | always-on  | ~1–2 GB   |
| Qwen3.6-27B (NVFP4) + KV      | always-on  | ~18–24 GB |
| Qwen3-Embedding-4B            | on-demand  | ~4–6 GB   |
| Qwen3-ASR-0.6B                | on-demand  | ~2–3 GB   |
| Qwen3-TTS-0.6B                | on-demand  | ~2 GB     |
| Docling + OCR                 | on-demand  | ~2–4 GB   |

Der Core belegt grob ~30 GB → reichlich Headroom, um Profile bei Bedarf dazuzuschalten.

## Tuning-Knöpfe (bei Startup-OOM)
- `LLM_GPU_MEM_UTIL` senken (vLLM reserviert KV-Cache vorab, wirkt "hungrig")
- `--enforce-eager` (in `LLM_EXTRA_ARGS`) — spart CUDA-Graph-Speicher
- `LLM_MAX_LEN` reduzieren; `LLM_KV_DTYPE=fp8` für langen Kontext
- **NVFP4** statt FP8/BF16 — Blackwell-nativ, kleinster Footprint
  (Größenordnung aus der Praxis: ein Modell 117 GB → 32 GB mit FP4 + enforce-eager + util 0.2)

## Automatisches Modell-Swapping (später)
Für mehrere LLMs, die sich den Pool teilen: `llama-swap` (VRAM-Eviction) oder
vLLM-Sleep-Mode vor den LLM-Dienst hängen. Für die heterogenen Audio/OCR-Container
reichen zunächst die Compose-Profile.
