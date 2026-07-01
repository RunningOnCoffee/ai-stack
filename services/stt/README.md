# STT — Qwen3-ASR-0.6B (on-demand, Profil `voice`)  [GEPLANT]

Exponiert OpenAI `/v1/audio/transcriptions`. Start: `make up-voice`.

## Basis
`AEON-7/qwen3-asr-server` (vLLM-nativ, sm_120/121, flash-attn 2) als Vorlage/Base.
Entweder deren Image als `STT_IMAGE` in `.env` setzen, oder hier ein `Dockerfile`
ablegen und `build:` in einem Override ergänzen.

## aarch64-Hinweis
Audio-Wheels (torchaudio, ctranslate2, flash-attn) sind auf aarch64 heikel — die
AEON-7-Server lösen das bereits. Sonst Community-Wheels/Source-Build (siehe docs).

## Einbindung
In `gateway/litellm-config.yaml` den `qwen3-asr`-Block einkommentieren, oder direkt
`http://stt:8000` aufrufen.
