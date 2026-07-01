# Phase 2 — Migration auf x86

Dank base+Override ändert sich nur wenig:

1. In `.env`:  `COMPOSE_FILE=compose/base.yml:compose/x86.yml`
2. `VLLM_IMAGE` auf ein Standard-amd64-Image setzen (z.B. `vllm/vllm-openai:<version>`)
3. `docker compose up -d`

Gleich bleiben: Service-Graph, Qdrant, LiteLLM-Config, Ports, App-Code.

## Was sich anbietet
- Embeddings alternativ über TEI (Text Embeddings Inference) statt vLLM
- OCR: Standard-PaddlePaddle-GPU (keine sm_121-Sonderwheels nötig)
- Kein sm_121/FlashInfer-Sonderfall, keine aarch64-Audio-Build-Fallen

## Ein Tag für beide Architekturen
Für eigene Images `docker buildx build --platform linux/amd64,linux/arm64 --push`
→ Multi-Arch-Manifest, dann trägt derselbe Tag arm64 (Spark) und amd64 (x86).
