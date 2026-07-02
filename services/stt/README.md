# STT — Qwen3-ASR-0.6B (on-demand, Profil `voice`)

Exponiert OpenAI `/v1/audio/transcriptions` (Host: `:8003`, im Compose-Netz:
`http://stt:8001` — Port 8001 ist der Upstream-Default des Images).
Start: `make up-stt` (oder `make up-voice` für STT + TTS zusammen).

## Basis
Fertiges ARM64/sm_121a-Image `ghcr.io/aeon-7/qwen3-asr-server` (Repo:
`AEON-7/qwen3-asr-server`) auf Grundlage von AEONs Spark-vLLM-Build — vLLM
serviert Qwen3-ASR nativ als OpenAI-Audio-Endpoint, die aarch64-Audio-Wheels
sind im Image gelöst. Healthcheck ist im Image eingebaut (prüft `8001/v1/models`
— deshalb den Container-Port nicht ändern).

Das `vllm serve`-Kommando liegt parametrisiert in `compose/arm64.yml`
(Werte: `STT_*` in `.env`). 30 Sprachen inkl. DE/EN, RTF ~16× Echtzeit.

## Setup
Kein manueller Schritt nötig: Das Modell (~1.3 GB) lädt der Container beim
ersten Start selbst in den geteilten HF-Cache (`HF_HOME`-Mount).

```bash
make up-stt
docker compose logs -f stt         # bis "Application startup complete"

# Test (WAV/MP3/OGG …, Feld "file" + "model"):
curl -s http://localhost:8003/v1/audio/transcriptions \
  -F file=@models/tts/test-de.wav -F model=qwen3-asr
```

## Qualitäts-Upgrade
`STT_MODEL_ID=Qwen/Qwen3-ASR-1.7B` in `.env` setzen und `STT_GPU_MEM_UTIL`
auf ≥ 0.10 erhöhen, dann `make up-stt` (lädt das neue Modell nach).

## Einbindung
`qwen3-asr` ist in `gateway/litellm-config.yaml` registriert; solange der
Dienst nicht läuft, schlagen am Gateway nur Anfragen an dieses Modell fehl.
Über das Gateway: `POST :4000/v1/audio/transcriptions` mit `model=qwen3-asr`.
