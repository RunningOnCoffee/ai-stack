# HOW-TO — Plattform nutzen (API, Apps, Open WebUI)

> Kurzreferenz aus Anwendungssicht. Betrieb/Setup der Dienste: `READ_THIS_CONTEXT.md`
> und die Runbooks unter `services/*/README.md`.

## Grundprinzip: eine Tür für alles

Es gibt **einen** Endpoint — das LiteLLM-Gateway auf Port **4000** — und der spricht
das **OpenAI-Protokoll**. Jede Bibliothek/App/UI, die mit der OpenAI-API umgehen kann,
funktioniert mit zwei geänderten Einstellungen:

| Einstellung | Wert |
|---|---|
| `base_url` | `http://<spark-ip>:4000/v1` (auf dem Spark selbst: `localhost`) |
| `api_key`  | `LITELLM_MASTER_KEY` aus der `.env` |

Die App wählt das Modell nur über das `model`-Feld:

| `model` | Dienst | Start |
|---|---|---|
| `qwen3.6-27b` | Qwen3.6-27B (Qualität, multimodal) | `make up` (always-on) |
| `qwen3.6-35b-fast` | Qwen3.6-35B-A3B MoE (Tempo) | `make up-fast` (on-demand) |
| `qwen3-tts` | Text→Sprache (DE/EN) | `make up-tts` |
| `qwen3-asr` | Sprache→Text (DE/EN, 30 Sprachen) | `make up-stt` |

Nicht gestartete Modelle schaden nicht: Nur Anfragen an genau dieses Modell schlagen fehl.

Direktzugriff an der LiteLLM vorbei (fürs Debugging): LLM `:8000`, llm-fast `:8001`,
TTS `:8002`, STT `:8003`, Qdrant `:6333`. Für Apps immer das Gateway nehmen —
ein Endpoint, ein Key, Modelle dahinter austauschbar, ohne die App anzufassen.

## LLM aus einer eigenen Applikation

```python
from openai import OpenAI

client = OpenAI(base_url="http://<spark-ip>:4000/v1", api_key="<master-key>")

antwort = client.chat.completions.create(
    model="qwen3.6-27b",
    messages=[{"role": "user", "content": "Fasse mir das zusammen: ..."}],
    stream=True,          # Streaming funktioniert
)
```

Gilt genauso für JavaScript, LangChain, LlamaIndex, n8n usw. — nur Base-URL und
Key umbiegen. **Tool-Calling/Function-Calling und Reasoning sind serverseitig
konfiguriert** (qwen3-Parser in vLLM) und funktionieren out of the box.

Dasselbe per `curl`:

```bash
curl http://<spark-ip>:4000/v1/chat/completions \
  -H "Authorization: Bearer <master-key>" -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Hallo!"}]}'
```

## Audio: TTS & STT

```python
# Text -> Sprache (Stimmen: serena-de, ryan, aiden, ... — GET :8002/v1/audio/voices)
wav = client.audio.speech.create(model="qwen3-tts", voice="serena-de",
                                 input="Hallo, ich bin die neue Stimme.")

# Sprache -> Text
text = client.audio.transcriptions.create(model="qwen3-asr",
                                          file=open("aufnahme.wav", "rb"))
```

```bash
curl http://<spark-ip>:4000/v1/audio/speech -H "Authorization: Bearer <master-key>" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-tts","input":"Hallo Welt.","voice":"serena-de"}' --output hallo.wav

curl http://<spark-ip>:4000/v1/audio/transcriptions \
  -H "Authorization: Bearer <master-key>" \
  -F file=@aufnahme.wav -F model=qwen3-asr
```

## Open WebUI anbinden

Open WebUI (noch nicht Teil des Stacks; ein Container ohne GPU-Bedarf, offizielles
ARM64-Image vorhanden) hängt sich komplett ans Gateway:

- **Chat:** *Admin → Einstellungen → Verbindungen* → OpenAI-Verbindung:
  URL `http://<spark-ip>:4000/v1` (im Compose-Netz: `http://gateway:4000/v1`),
  Key = Master-Key. Die Modelle erscheinen automatisch (via `/v1/models`).
- **TTS (Vorlesen):** *Admin → Audio → TTS*: Engine „OpenAI", gleiche URL + Key,
  Modell `qwen3-tts`, Voice z. B. `serena-de`.
- **STT (Diktieren/Anruf-Modus):** *Admin → Audio → STT*: Engine „OpenAI",
  gleiche URL + Key, Modell `qwen3-asr`. Zusammen mit TTS funktioniert dann der
  Sprachdialog (sprechen → Text → LLM → Antwort vorgelesen), komplett lokal.

Als Compose-Service wären das im Kern diese Umgebungsvariablen:

```yaml
environment:
  OPENAI_API_BASE_URL: http://gateway:4000/v1
  OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
  AUDIO_TTS_ENGINE: openai
  AUDIO_TTS_OPENAI_API_BASE_URL: http://gateway:4000/v1
  AUDIO_TTS_MODEL: qwen3-tts
  AUDIO_TTS_VOICE: serena-de
  AUDIO_STT_ENGINE: openai
  AUDIO_STT_OPENAI_API_BASE_URL: http://gateway:4000/v1
  AUDIO_STT_MODEL: qwen3-asr
```

## RAG (Ausbaustufe, Schritt 3)

Embeddings/Reranker laufen noch nicht. Qdrant (`:6333`) ist aber schon ansprechbar —
eigene RAG-Apps können die Vektor-DB direkt nutzen. Sobald `qwen3-embedding` läuft,
wird es wie alles andere über das Gateway angesprochen (`client.embeddings.create(...)`).

## Vor echter Nutzung im LAN

- **Master-Key in `.env` ändern** (`sk-local-changeme` ist ein Platzhalter) und
  Gateway neu starten (`docker compose up -d gateway`).
- Die Ports sind auf `0.0.0.0` gebunden, also im Netz erreichbar.
  TLS/Reverse-Proxy ist bewusst erst Härtungs-Schritt 4 (siehe READ_THIS_CONTEXT.md).
