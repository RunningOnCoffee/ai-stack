# TTS — Qwen3-TTS-0.6B CustomVoice (on-demand, Profil `voice`)

Exponiert OpenAI `/v1/audio/speech` (Host: `:8002`, im Compose-Netz: `http://tts:8000`).
Start: `make up-tts` (STT ist noch nicht eingerichtet, daher nicht `make up-voice`).

## Basis
Fertiges ARM64/sm_121-Image `martinb78/faster-qwen3-tts-dgx-spark` (MIT) auf Grundlage
von `andimarafioti/faster-qwen3-tts` — CUDA-Graph statt Flash-Attention, löst die
aarch64-Audio-Wheel-Probleme. Wichtig: Die Server-Skripte sind NICHT im Image,
sie kommen aus dem Upstream-Repo und werden als `/config` gemountet.

## Setup (einmalig, auf neuem Host)
```bash
# 1. Upstream-Repo mit den Server-Skripten klonen (gitignored):
git clone --depth 1 https://github.com/mARTin-B78/dgx-spark-faster-qwen3-tts \
  services/tts/upstream

# 2. Modell herunterladen (~1.5 GB, Zielpfad = TTS_MODEL_DIR in .env):
hf download Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice \
  --local-dir models/tts/Qwen3-TTS-12Hz-0.6B-CustomVoice

# 3. Starten & testen:
make up-tts
curl -s http://localhost:8002/v1/audio/speech -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-tts","input":"Hallo, ich bin die neue Stimme.","voice":"serena-de"}' \
  --output /tmp/test.wav
```

## Stimmen (DE/EN)
`services/tts/customvoice_voices.json` überlagert die Upstream-Voices und definiert
u. a. `ryan`/`serena`/`aiden`/`vivian` (Sprache "Auto" — erkennt DE/EN am Text) sowie
explizite Varianten `ryan-de`, `ryan-en`, `serena-de`, `serena-en`.
Liste zur Laufzeit: `GET /v1/audio/voices`.

## Qualitäts-Upgrade
`Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` (~6 GB bf16) herunterladen und
`TTS_MODEL_DIR` in `.env` umstellen. Für Streaming/VoiceClone/VoiceDesign bringt das
Upstream-Repo eigene Server-Skripte mit (siehe dessen `docker/docker-compose.yml`).

## Alternative für deutsche Natürlichkeit
Chatterbox-Multilingual (MIT, 23 Sprachen) als zweites Backend, z. B. via
`devnen/Chatterbox-TTS-Server` (OpenAI-kompatibel) — auf eigenem DE-Text A/B-testen.

## Einbindung
`qwen3-tts` ist in `gateway/litellm-config.yaml` registriert; solange der Dienst
nicht läuft, schlagen am Gateway nur Anfragen an dieses Modell fehl.
