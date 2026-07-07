# HOW-TO — Plattform nutzen (API, Apps, LibreChat)

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
| `qwen3.6-27b-instant` | derselbe 27B **ohne Thinking** (Titel, Zusammenfassungen, schnelle Hilfsaufgaben; 0 extra Speicher) | `make up` (Alias) |
| `qwen3.6-35b-fast` | Qwen3.6-35B-A3B MoE (Tempo) | `make up-fast` (on-demand) |
| `qwen3-tts` | Text→Sprache (DE/EN) | `make up-tts` |
| `qwen3-asr` | Sprache→Text (DE/EN, 30 Sprachen) | `make up-stt` |

Nicht gestartete Modelle schaden nicht: Nur Anfragen an genau dieses Modell schlagen fehl.

> ⚠️ **GPU-Budget:** `llm-fast` (0.30) und das Voice-Profil (TTS + STT) passen
> **nicht gleichzeitig** neben den 27B (0.50) — STT crasht dann beim Start mit
> CUDA out of memory (Restart-Schleife). Vor `make up-voice` also
> `make stop-fast` ausführen (und umgekehrt bei Bedarf Voice stoppen).

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
# Default am Gateway ist MP3 (Browser-kompatibel); WAV via response_format="wav".
mp3 = client.audio.speech.create(model="qwen3-tts", voice="serena-de",
                                 input="Hallo, ich bin die neue Stimme.")

# Sprache -> Text
text = client.audio.transcriptions.create(model="qwen3-asr",
                                          file=open("aufnahme.wav", "rb"))
```

```bash
curl http://<spark-ip>:4000/v1/audio/speech -H "Authorization: Bearer <master-key>" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-tts","input":"Hallo Welt.","voice":"serena-de","response_format":"wav"}' \
  --output hallo.wav    # ohne response_format kommt MP3 (Gateway-Default)

curl http://<spark-ip>:4000/v1/audio/transcriptions \
  -H "Authorization: Bearer <master-key>" \
  -F file=@aufnahme.wav -F model=qwen3-asr
```

## LibreChat — die Chat-UI des Stacks

LibreChat (MIT-Lizenz) ist Teil des Compose-Stacks und komplett vorkonfiguriert
(`services/librechat/librechat.yaml`): Chat, Vorlesen (TTS) und Diktieren (STT)
laufen über das Gateway. Details/Entscheidung: `services/librechat/README.md`.

- **Start:** `make up` (Core) bzw. `make up-voice` für den Sprachdialog;
  `make up-ui` startet nur UI + MongoDB (ohne GPU-Dienste).
- **Aufruf:** `http://<spark-ip>:3080` → ersten Account registrieren → Endpoint
  „AI-Stack", Modell `qwen3.6-27b`.
- **Sprache:** Einstellungen → Sprache → **Engine bei STT und TTS auf
  „External" stellen** (einmalig pro Browser/Profil; der Default „Browser"
  nutzt die Web-Speech-API des Browsers statt unseres Stacks — liest dann
  u. a. den Think-Block mit vor). Liest auch „External" einen „Thinking"-Block
  mit vor: einmal Hard-Reload (Strg+Shift+R) — die Anti-Think-Patches sind an
  die Image-Version gebunden (`services/librechat/README.md`). Voice z. B. `serena-de`
  (alle: `services/tts/customvoice_voices.json`); die Modelle `qwen3-asr`/
  `qwen3-tts` sind serverseitig vorkonfiguriert (`librechat.yaml`).
  Sprechen → Text → LLM → Antwort vorgelesen, komplett lokal.
- **Neue Chat-Modelle** müssen in `gateway/litellm-config.yaml` **und**
  `services/librechat/librechat.yaml` (`models.default`) eingetragen werden
  (`fetch: false`, damit TTS/ASR nicht im Chat-Dropdown landen).

Jede andere OpenAI-kompatible UI (z. B. Open WebUI) funktioniert nach demselben
Prinzip gegen das Gateway — LibreChat wurde wegen der MIT-Lizenz gewählt
(rebrand-/produktisierbar; Open WebUI hat seit 04/2025 eine Branding-Klausel).

## RAG (Ausbaustufe, Schritt 3)

Embeddings/Reranker laufen noch nicht. Qdrant (`:6333`) ist aber schon ansprechbar —
eigene RAG-Apps können die Vektor-DB direkt nutzen. Sobald `qwen3-embedding` läuft,
wird es wie alles andere über das Gateway angesprochen (`client.embeddings.create(...)`).

## Vor echter Nutzung im LAN

- **Master-Key in `.env` ändern** (`sk-local-changeme` ist ein Platzhalter) und
  Gateway neu starten (`docker compose up -d gateway`).
- **LibreChat:** offene Registrierung abwägen — `ALLOW_REGISTRATION` in
  `compose/base.yml` auf `"false"` setzen, sobald alle Team-Accounts angelegt
  sind (Secrets liegen in `.env`, siehe `.env.example`).
- Die Ports sind auf `0.0.0.0` gebunden, also im Netz erreichbar.
  TLS/Reverse-Proxy ist bewusst erst Härtungs-Schritt 4 (siehe READ_THIS_CONTEXT.md).
