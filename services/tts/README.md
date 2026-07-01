# TTS — Qwen3-TTS-0.6B (on-demand, Profil `voice`)  [GEPLANT]

Exponiert OpenAI `/v1/audio/speech` (97 ms First-Packet-Streaming). Start: `make up-voice`.

## Basis
`AEON-7/qwen3-tts-server` oder `mARTin-B78/dgx-spark-faster-qwen3-tts`
(CUDA-Graph-Beschleunigung, mehrere Voice-Backends) als Vorlage.

## Alternative für deutsche Natürlichkeit
Chatterbox-Multilingual (MIT) als zweites Backend — auf eigenem DE-Text A/B-testen.

## Einbindung
`qwen3-tts`-Block in `gateway/litellm-config.yaml`, oder direkt `http://tts:8000`.
