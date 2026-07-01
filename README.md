# Lokaler AI-Stack

Selbstgehosteter AI-Stack für **DGX Spark (GB10 / aarch64 / sm_121)**, portierbar nach x86.
Alle Modelle 0–100B, Fokus Qualität für Deutsch + Englisch. Ein OpenAI-kompatibler Endpoint
(LiteLLM) vor getierten Inferenz-Engines.

## Architektur

```
Clients ──► LiteLLM (:4000)  ──►  vLLM / Qwen3.6-27B   (LLM + Doc-VLM)   [core]
                │                  vLLM / Qwen3-Embedding + Reranker      [rag]
                │                  Qwen3-ASR  /v1/audio/transcriptions    [voice]
                │                  Qwen3-TTS  /v1/audio/speech            [voice]
                │                  Docling + PaddleOCR-VL                 [rag]
                └──► Qdrant (:6333)  Vektor-DB (dense + sparse)          [core]
```

**Betriebsmodell:** Kernservices (LiteLLM, Qdrant, LLM) laufen **always-on**
(`restart: unless-stopped`, kein Profil). Voice- und RAG-Dienste sind **on-demand**
über Compose-Profile (`voice`, `rag`) — man startet sie bei Bedarf, weil sich alle
Modelle die **128 GB Unified Memory** teilen. Siehe `docs/memory-budget.md`.

## Getroffene Entscheidungen

| Thema        | Wahl                                             |
|--------------|--------------------------------------------------|
| Betrieb      | Kernservices always-on, Rest on-demand (Profile) |
| Vektor-DB    | Qdrant (schlank, dense + sparse)                 |
| Reihenfolge  | LLM zuerst (Qwen3.6-27B) → Voice → RAG           |
| Multi-Arch   | `base` + Arch-Override (`arm64` zuerst, `x86` später) |
| Build        | Community-/NVIDIA-Prebuilts, später gepinnte Eigen-Builds |

## Voraussetzungen

- DGX Spark mit DGX OS (aarch64), CUDA 13.x, `nvidia-smi` funktioniert
- Docker + NVIDIA Container Toolkit (`docker run --gpus all nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04 nvidia-smi`)
- Hugging-Face-Token (für Modell-Downloads)
- Erst-Setup + Gotchas: **`docs/spark-setup.md` lesen** (aarch64-Fallen sind real)

## Quickstart

```bash
cp .env.example .env
#  In .env eintragen:
#   - HF_TOKEN
#   - VLLM_IMAGE  → aktuellen sm_121-Digest pinnen (siehe docs/spark-setup.md)
#   - LLM_MODEL_ID → gewünschte Qwen3.6-27B-Variante (idealerweise NVFP4)

# COMPOSE_FILE in .env merged base + arm64 automatisch:
docker compose up -d          # startet die Core-Services (LiteLLM, Qdrant, LLM)
docker compose logs -f llm    # Ladefortschritt beobachten

# Test:
curl http://localhost:4000/v1/models
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Sag Hallo auf Deutsch."}]}'
```

Oder via `make up`. On-demand später: `make up-voice` / `make up-rag`.

## Struktur

```
ai-stack/
├── compose/          base.yml + arm64.yml + x86.yml (Override-Pattern)
├── gateway/          LiteLLM-Config (ein Endpoint → alle Backends)
├── services/         llm · stt · tts · embedding · ocr (je Runbook)
├── infra/            vectordb · proxy · monitoring
├── images/           gepinnte Eigen-Builds (Phase 2, buildx)
└── docs/             spark-setup · memory-budget · x86-migration
```

## Roadmap (nach und nach)

- [x] **Core:** LiteLLM + Qdrant + Qwen3.6-27B (dieses Gerüst)
- [ ] **Voice:** Qwen3-ASR + Qwen3-TTS (`make up-voice`) — Basis: `AEON-7/qwen3-asr-server`, `AEON-7/qwen3-tts-server`
- [ ] **RAG:** Qwen3-Embedding + Reranker + Docling/PaddleOCR-VL (`make up-rag`)
- [ ] **Härten:** Reverse Proxy (TLS), Monitoring (GB10-UMA), gepinnte Eigen-Images via GitHub Actions
- [ ] **x86:** `COMPOSE_FILE` auf `base:x86` umstellen (siehe `docs/x86-migration.md`)

## Referenzen (DGX Spark)

- `NVIDIA/dgx-spark-playbooks` — offizielle Playbooks (vLLM, SGLang, Ollama, …)
- `bidual/awesome-dgx-spark` — kuratierte Liste
- `hellohal2064/vllm-dgx-spark-gb10` — vLLM sm_121, verifiziert mit Qwen3-Embedding-8B / Qwen3-VL-30B
- `eugr/spark-vllm-docker`, `scitrera/dgx-spark-vllm` — Community-Standard-Images
- `AEON-7/qwen3-asr-server`, `AEON-7/qwen3-tts-server` — OpenAI-kompatible Audio-Server für Qwen3
