# AI-Stack auf DGX Spark — Projekt-Kontext & Fortsetzung

> **Zweck dieses Dokuments:** Vollständiger Kontext zum Weitermachen in einer neuen
> Konversation. Enthält Ziel, Modellauswahl, aktuellen Stand,
> Repo-Struktur, die DGX-Spark-Fallstricke und die konkreten nächsten Schritte mit
> fertiger Konfiguration. Stand: Juli 2026.

---

## 0. ⚡ UPDATE 03.07.2026 — aktueller Stand (zuerst lesen!)

### Was läuft / was ist fertig

| Baustein | Status | Start | Endpoint |
|---|---|---|---|
| LLM Qwen3.6-27B (NVFP4, vLLM) | ✅ läuft, getestet | `make up` | `:8000` |
| llm-fast Qwen3.6-35B-A3B (MoE) | ✅ getestet, bewusst on-demand | `make up-fast` | `:8001` |
| TTS Qwen3-TTS-0.6B CustomVoice (DE/EN) | ✅ eingerichtet | `make up-tts` | `:8002` |
| STT Qwen3-ASR-0.6B (DE/EN, 30 Sprachen) | ✅ läuft, getestet (direkt + Gateway) | `make up-stt` | `:8003` |
| Gateway (LiteLLM) + Qdrant | ✅ laufen, Erst-Test bestanden (alle 4 Routen) | `make up` | `:4000` / `:6333` |
| **Chat-UI LibreChat + MongoDB (neu, Session 4)** | ✅ läuft, E2E-getestet (Chat via 27B, STT, TTS über Gateway) | `make up` / `make up-ui` | `:3080` |

### Session 4 (03.07.): Front-end-Entscheidung + LibreChat integriert
- **Entscheidung: LibreChat statt Open WebUI** (Recherche 03.07.): Open WebUI
  seit v0.6.6 (04/2025) Custom-Lizenz mit Branding-Klausel (>50 User) + CLA,
  nicht OSI; LibreChat pures MIT (seit 11/2025 ClickHouse, MIT-Zusage
  öffentlich) → rebrand-/produktisierbar. Details: `services/librechat/README.md`.
- **Bewusst ohne rag_api/pgvector/Meilisearch** (LibreChat-RAG ist naiv:
  Fixed-Chunks, dense-only, kein Rerank; OCR-Default = Mistral-Cloud).
  **RAG-Plan geändert:** eigener **MCP-Retrieval-Server** (streamable-http,
  `mcpServers` in `librechat.yaml`, von LibreChat-Agents genutzt):
  Query → Embedding (Gateway) → Qdrant (hybrid) → Reranker → Passagen+Quellen;
  Ingestion (OCR → Chunking → Embedding → Qdrant) entkoppelt als eigene Pipeline.
- Neu: `compose/base.yml` Services `librechat` + `mongodb` (Core, ohne Profil),
  `services/librechat/` (librechat.yaml + README), `LIBRECHAT_*`/`MONGO_IMAGE`
  in `.env`/`.env.example` (Secrets via openssl, siehe Vorlage), `make up-ui`.
- Gotchas: LibreChat-Image ohne curl → node-Healthcheck; MongoDB ohne Auth,
  dafür ohne Host-Port; `models.fetch: false`, damit qwen3-tts/-asr nicht im
  Chat-Dropdown landen — neue Chat-Modelle in Gateway-Config UND
  `librechat.yaml` pflegen; MongoDB ist SSPL (intern ok).
- **E2E verifiziert (03.07., per API):** Chat → „Bereit" vom 27B (Antwort
  liegt in `content`-Blöcken [think]+[text], Feld `text` bleibt leer);
  STT (test-de.wav korrekt transkribiert) + TTS (Audio zurück) über
  LibreChats Speech-Routen; Voices-Liste = librechat.yaml. Weitere Gotchas:
  v0.8.7-Chat-API = `POST /api/agents/chat/:endpoint` (resumable streams:
  POST antwortet sofort mit streamId, Generierung läuft serverseitig);
  Browser-User-Agent nötig (uaParser lehnt Skript-UAs ab: „Illegal request");
  Login-Rate-Limiter greift schnell. **Der erste registrierte User wird
  Admin** — Test-User wurden gelöscht; Bruno ist registriert (ADMIN).
- **Non-Thinking-Alias `qwen3.6-27b-instant`** (Gateway): derselbe 27B mit
  `extra_body: chat_template_kwargs.enable_thinking=false` — gemessen
  98s/960 Tokens (Thinking) vs. 1s/9 Tokens (ohne) beim Titel-Prompt.
  LibreChat-`titleModel` nutzt ihn (`titleConvo: true`, E2E getestet:
  Titel in Sekunden, 0 Timeouts). Kein separates Klein-LLM nötig; erneut
  prüfen, falls parallele Hilfslast steigt (Budget erst für RAG nutzen).
  Gotcha: Stock-Titel-Prompt titelt teils englisch (kosmetisch).
- **TTS-im-Browser-Fix (03.07.):** LibreChat sendet kein `response_format`
  und setzt hart `audio/mpeg` — unser TTS lieferte aber WAV → stumme
  Wiedergabe. Fix: Gateway-Default `response_format: mp3` am qwen3-tts-Eintrag
  (Clients können weiter explizit WAV anfordern; beides verifiziert).
  Zweiter TTS-Fix: Vorlesen las den **Think-Block** mit (2 Upstream-Bugs,
  auch auf main: skipReasoning-Default + geparster Text wurde nie benutzt)
  → Patch `services/librechat/patches/streamAudio.js` als ro-Mount (an
  v0.8.7 gebunden, beim Image-Update prüfen; README). Verifiziert:
  Audio 139 KB → ~6 KB (nur die Antwort). Client-seitig 2 weitere
  Upstream-Bugs (Details services/librechat/README.md): Klick-Vorlesen
  parst den Text client-seitig inkl. Think *(Korrektur Session 5: die
  damalige Deutung „Cache-Toggle wählt den Code-Pfad" war falsch — der
  Klick geht immer über /tts/manual, s. u.)*; und stale CacheStorage
  `tts-responses` überlebt Hard-Reload. Insgesamt 5 diagnostizierte
  Upstream-Bugs (Issue/PR-Paket wert).
- `interface.runCode: false` in librechat.yaml: der „Run Code"-Button
  ruft LibreChats gehostete Cloud-API auf (api.librechat.ai, 401 ohne Key) —
  nicht souverän; reaktivieren, falls die Code-API self-hosted verfügbar wird.

### ✅ GELÖST (Session 5, 07.07.): TTS las Think vor — ZWEI Ursachen
Der „TTS liest Think trotz sauberem Server-Pfad"-Mystery aus Session 4 ist
aufgeklärt — es waren **zwei gestaffelte Ursachen**:
1. **LibreChats Default-Engine für TTS UND STT ist `browser`** (Web Speech
   API, rein client-seitig; Bundle: `engineTTS/engineSTT = 'browser'`) —
   liest den Roh-Text inkl. Think, bricht bei langen Texten ab (Chrome-
   speechSynthesis), **kein Server-Request** (so per Debug-Log + Inkognito-
   Test bewiesen). Fix (einmalig pro Browser/Profil, localStorage):
   Einstellungen → Sprache → Engine bei STT **und** TTS auf **„External"**.
2. Auch mit „External": **Der Vorlese-Button geht IMMER über `/tts/manual`
   mit client-seitig gebautem Text inkl. Think** — der TTS-Cache-Toggle
   wechselt die Route NICHT (Session-4-Notiz „Cache AN = Streaming-Route"
   war falsch; die gepatchte Streaming-Route nutzt nur `automaticPlayback`).
   Bewiesen via MongoDB (Antwort 87 Zeichen ≈ 6s) vs. TTS-Log (60s Audio =
   Think+Antwort). Fix: **2. Patch `patches/hooks.Bi3Cm4Qy.js`** (1 Byte:
   Client-Parser `by()` = parseTextParts auf skipReasoning=true), ro-Mount
   in base.yml — Details/Update-Caveats services/librechat/README.md.
   Dazu **3. Patch `patches/sw.js`**: Workbox-Precache führt das Bundle
   mit `revision:null` → installierte Service Worker refetchen es sonst
   NIE (übersteht Hard-Reloads); Revision-Bump „think-patch-1" lässt alle
   Clients das gepatchte Bundle beim nächsten Seitenaufruf ziehen.
3. **Backstop (weil Browser-Cache-Zombies real sind): 4. Patch
   `patches/TTSService.js`** — serverseitiger Think-Filter direkt in der
   manuellen TTS-Route, cache-unabhängig: Exakt-Abgleich des Inputs gegen
   die letzten User-Nachrichten in der DB (Think+Antwort → nur Antwort;
   der geleakte Think hat KEINE `<think>`-Tags, reine Regex reicht nicht)
   + Tag-Regex als Fallback. Toggle `TTS_READ_THINK=true` (.env) schaltet
   ihn ab. E2E getestet (230-Zeichen-Tag-Input → 3,25 s Audio).
- **Upstream-Bug #5:** Ein External-Default per `librechat.yaml`
  (`speech.speechTab.textToSpeech.engineTTS`) ist in v0.8.7 unmöglich —
  das yaml-Schema erlaubt nur `openai/azureOpenAI/elevenlabs/localai`, der
  Client kennt aber nur `browser/external` und **resettet fremde Werte auf
  `browser`** (hooks-Bundle: „Resetting invalid TTS engine"). Damit insgesamt
  5 diagnostizierte Upstream-Bugs (services/librechat/README.md).
- DEBUG_LOGGING/DEBUG_CONSOLE (temporäre Diagnose) wieder entfernt.
- **Gotcha (live erlebt): llm-fast + Voice-Profil sprengen das GPU-Budget** —
  `ai-stt` crasht dann beim Start mit CUDA out of memory in einer
  Restart-Schleife (0.50 LLM + 0.30 llm-fast + TTS + 0.08 STT > ~0.85).
  Fix: `make stop-fast` (neues Target) vor `make up-voice`; Warnung in
  HOW-TO.md (Modell-Tabelle). Zwei Folge-Gotchas aus demselben Vorfall:
  (a) **ai-tts bleibt bei OOM oben und meldet healthy** (Healthcheck prüft
  nur den HTTP-Server, nicht das Modell) — Requests liefern dann
  503 „Model not loaded"; nach OOM `docker compose --profile voice restart tts`
  (Modell-Load + CUDA-Warmup abwarten, erst danach nimmt er Requests an).
  (b) **Gateway hält stale Verbindungen zu neu gestarteten Backends**
  (Container-IP wechselt beim Recreate/Restart) — Symptom:
  `APIConnectionError` am Gateway, obwohl das Backend direkt erreichbar ist
  und dort kein Request ankommt; Fix: `docker compose restart gateway`.
  Danach Voice-E2E übers Gateway erneut verifiziert (TTS→WAV→STT-Roundtrip
  + MP3-Default).
- Noch offen (klein): STT-Browsertest — Mikrofonzugriff braucht
  HTTPS/localhost-Tunnel (kommt mit Härtungs-Schritt 4, TLS/Reverse-Proxy).

**Nutzung aus Anwendungssicht (API, Open WebUI, …): siehe `HOW-TO.md`.**

### Wichtige Abweichungen von den älteren Abschnitten dieses Dokuments
- **vLLM-Image ist `nvcr.io/nvidia/vllm:26.04-py3`** — nicht cu130-nightly (Abschnitt 6
  war veraltet, unten korrigiert) und **nicht 26.06** (dessen API-Server ist kaputt:
  prometheus-fastapi-instrumentator 8.0.0 + starlette 1.3.1 → jede Anfrage HTTP 500).
- **Modell ist `unsloth/Qwen3.6-27B-NVFP4`** (nicht ocicek). Die Gewichte kommen aus dem
  wiederverwendeten Cache des alten Setups: `HF_HOME=/srv/docker/ai-stack-2/vllm/models/hf-cache`
  (133 GB — **ai-stack-2 nicht löschen!**).
- `LLM_MODEL_ID` zeigt als **lokaler Snapshot-Pfad** in den Cache, weil unsloth die
  Gewichte upstream geändert hat (Repo-ID = ~26 GB Neu-Download) und vLLM `--revision`
  fälschlich auch aufs Tokenizer-Repo anwendet (404 RevisionNotFound).

### Zusätzlich gelernte Gotchas (ergänzend zu Abschnitt 7)
- **Relative Pfade in den compose-Dateien** löst Compose relativ zu `compose/` auf, nicht
  zum Projektroot → in base.yml `../gateway/...` etc. (der Gateway-Mount war deshalb
  kaputt; gefixt. Leiche `compose/models/` kann weg, braucht sudo).
- **nvcr-vLLM-Images haben keinen vllm-Entrypoint** → volles `vllm serve ...` als
  command nötig (`vllm/vllm-openai`-Images hätten ihn eingebaut).
- `~/.cache/huggingface` gehört root (Altlast) → `hf download` als spark mit
  `HF_HOME=/srv/docker/ai-stack/models/.hf-home` aufrufen (oder einmalig
  `sudo chown -R spark:spark ~/.cache/huggingface`).
- **TTS-Server-Skripte sind NICHT im TTS-Image** — sie kommen aus dem gitignorten Klon
  `services/tts/upstream/` (Setup-Schritte: `services/tts/README.md`).
- **LiteLLM-Image hat kein curl/wget** → Gateway-Healthcheck als python3-Probe
  (base.yml); der Dienst lief, wurde aber fälschlich "unhealthy" angezeigt.
- **STT-Image (AEON-7) lauscht intern auf 8001** (Upstream-Default; der im Image
  eingebaute Healthcheck prüft fest auf 8001) → Container-Port nicht umbiegen,
  Mapping ist `8003:8001`.
- **LiteLLM `openai/`-Provider erzwingt bei Transkription `response_format=verbose_json`**,
  das vLLM nicht kann (auch `additional_drop_params` hilft nicht) → für ASR den
  Provider `hosted_vllm/` verwenden (Fix: BerriAI/litellm PR #15010).

### Erledigt 02.07. (Session 3): STT (Schritt 2b) + Gateway-Erst-Test
- STT via `ghcr.io/aeon-7/qwen3-asr-server` (ARM64/sm_121a, vLLM-nativ, ~13-GB-Image,
  eingebauter Healthcheck): `make up-stt`, Port 8003, `Qwen/Qwen3-ASR-0.6B`
  (lädt der Container beim Erststart selbst, ~1.3 GB). DE + EN getestet — direkt
  und über das Gateway (Testdateien: `models/tts/test-*.wav` = TTS-Ausgaben,
  d. h. Rundlauf Sprache→Text→Sprache verifiziert). Runbook: `services/stt/README.md`.
- Gateway + Qdrant Erst-Test bestanden: alle 4 Modelle gelistet, Chat (27B),
  TTS (gültige WAV) und ASR (DE/EN) über `:4000` verifiziert; Qdrant ready.
- `HOW-TO.md` neu: Nutzung per API/SDK, Open WebUI-Anbindung (Chat/TTS/STT), Ports.

### Nächster Schritt: RAG (Schritt 3) — eigener Stack + MCP-Anbindung
- **RAG-Dienste:** `make up-rag` — Embedding (`--task embed`, command liegt
  schon in arm64.yml, `EMBED_MODEL_ID=Qwen/Qwen3-Embedding-4B`, Util 0.10)
  + Reranker (`--task score`, `RERANK_MODEL_ID=Qwen/Qwen3-Reranker-4B`)
  + OCR (zuerst Granite-Docling-258M, dann PaddleOCR-VL — Abschnitt 8, Schritt 3).
  `qwen3-embedding` in `gateway/litellm-config.yaml` einkommentieren.
- **MCP-Retrieval-Server** (dünn, CPU): Tool `search_knowledge` → Embedding via
  Gateway → Qdrant (hybrid) → Reranker → Passagen+Quellen; Anbindung über
  `mcpServers` (streamable-http) in `services/librechat/librechat.yaml`,
  Nutzung über einen geteilten LibreChat-Agent. Ingestion-Pipeline separat
  (OCR → Chunking → Embedding → Qdrant), als On-demand-Job.
- Danach gemeinsam optimieren (27B ggf. auf 0.35, Quoten-Summe ≤ 0.85).
- Vor LAN-Nutzung: `LITELLM_MASTER_KEY` ändern (Platzhalter `sk-local-changeme`)
  und LibreChat-Registrierung schließen (`ALLOW_REGISTRATION: "false"`).
- Repo-Hygiene erledigt (Session 3): `.env.example` mit `.env` synchronisiert
  (inkl. 26.04-Image-Warnung, LLM-fast/TTS/STT-Blöcke) — beim Ändern der `.env`
  die Vorlage bitte mitpflegen. `.env` selbst war und ist NICHT getrackt.

### TTS-Modell-Recherche (07/2026, für später)
Qwen3-TTS = beste Wahl (Apache 2.0, ~97 ms, DE/EN). Alternativen: CosyVoice 3 (Apache 2.0),
Chatterbox Multilingual (MIT, A/B-Test für DE-Feinschliff), NVIDIA Magpie (Open Model
License), Voxtral TTS (Mistral, stark, aber **CC-BY-NC** → nicht kommerziell).

---

## 1. Ziel & Rahmenbedingungen

- Selbstgehosteter AI-Stack, **alle Modelle 0–100B Parameter**, Fokus **Qualität**.
- **Deutsch + Englisch** (multilinguale Retrieval-/Sprachqualität ist durchgängig wichtig).
- Alles läuft **lokal / on-prem**, containerisiert via **docker compose**, ein
  OpenAI-kompatibler Endpoint (**LiteLLM**) vor getierten Inferenz-Engines.
- Hardware zuerst **DGX Spark (ARM/aarch64)**, später portierbar nach **x86**.
- **Inkrementeller** Aufbau ("nach und nach"), Teamprojekt.

## 2. Hardware: DGX Spark (GB10) — die wichtigsten Fakten

- GB10 Superchip: **ARM64 Grace CPU + Blackwell GPU**, ein gemeinsamer Pool von
  **128 GB Unified Memory** (CPU+GPU teilen sich denselben Speicher).
- CUDA-Architektur **sm_121 / sm_121a**, CUDA 13.x, DGX OS vorinstalliert
  (Docker + NVIDIA Container Toolkit bereits einsatzbereit).
- **NVFP4** (4-bit float) ist Blackwell-nativ → bevorzugte Quantisierung (kleinster
  Footprint, volle FP4-Tensor-Core-Geschwindigkeit).

## 3. Der komplette Modell-Stack (Entscheidungen)

Alle Bausteine sind bewusst gewählt; der Großteil stammt aus dem **Qwen-Ökosystem**
(vereinfacht Serving/Wartung). Primär-Pick fett.

### 3.1 Text-LLM
- **Qwen3.6-27B** (dense, Apache 2.0, nativ multimodal) — Allrounder + zugleich
  Dokument-VLM. **docker compose up -d und test steht aus** (siehe Abschnitt 5).
- **Qwen3.6-35B-A3B** (MoE, 35B total / 3B aktiv) — als **schnelle Option**
  ("llm-fast"), wird als Nächstes hinzugefügt (Schritt 1).
- Alternativen: Gemma 4 31B (mehrsprachig, OCR/Charts), Mistral Small 4 24B.
- Mehr VRAM: Qwen3-Next-80B-A3B, Llama 3.3 70B (text-only), GPT-OSS 20B.
- **Über dem 100B-Limit, ausgeschlossen:** GLM-5.2 (754B), DeepSeek V4 (685B),
  Kimi K2.7 (~1T), Qwen 3.5 (397B). **Qwen 3.7** ist proprietär/API-only.

### 3.2 STT — Live-Sprachdialog
- **Qwen3-ASR-0.6B** (Apache 2.0, Streaming+Offline, ~92 ms TTFT, 52 Sprachen inkl.
  DE/EN). Qualitätsvariante: 1.7B.
- Latenz-optimale Alternative: **Nemotron 3.5 ASR Streaming 0.6B** (Cache-Aware,
  sub-100 ms) — ⚠ HF-Zugang aktuell gated, NVIDIA-Lizenz prüfen.
- Bewährt: Whisper large-v3 via Faster-Whisper / WhisperX.
- Sprecher-Diarization (nur bei Mehr-Personen-Dialog): pyannote.audio 4.0 (Community-1).
- End-to-End-Alternative: Qwen3-Omni-30B-A3B (ASR+LLM+Sprachausgabe, Turn-Taking).

### 3.3 TTS — natürliche Sprachausgabe DE/EN
- **Qwen3-TTS-0.6B** (97 ms First-Packet-Streaming, Apache 2.0, 10 Sprachen inkl. DE,
  3s-Voice-Cloning). Qualität: 1.7B.
- German-Feinschliff-Alternative: Chatterbox-Multilingual (MIT; schlug ElevenLabs im Blindtest).
- Qualitäts-König: Fish Audio S2 Pro — ⚠ kommerzielle Self-Hosting-Lizenz kostenpflichtig, 4.4B.
- **Tipp:** Qwen3-TTS vs. Chatterbox auf eigenem deutschem Text A/B-testen.

### 3.4 OCR / Dokumente (zwei Ebenen)
- Framework: **Docling** (MIT) — PDF/DOCX/… → Markdown/JSON/DocTags, Layout/Tabellen/
  Lesereihenfolge, RAG-Chunking. Modell: **Granite-Docling-258M** (Apache 2.0, Latein-
  Schrift = DE/EN gut, stark bei Tabellen).
- Erkennung (max. Genauigkeit): **PaddleOCR-VL** (0.9B, 109 Sprachen inkl. DE).
- Spezialisierte OCR-VLMs: GLM-OCR (0.9B, OmniDocBench-König), dots.ocr (1.7B),
  DeepSeek-OCR (3B).
- Verständnis/Q&A über Dokumente: Qwen3-VL (2–32B) oder direkt Qwen3.6-27B.
- Schwachstelle bei allen: Handschrift.

### 3.5 Embedding / RAG (zwei Stufen)
- **Qwen3-Embedding** (0.6/4/8B) + **Qwen3-Reranker** (Apache 2.0, #1 auf MMTEB,
  100+ Sprachen, Matryoshka). Retrieval → Rerank über Top-K.
- Pragmatische Alternative: BGE-M3 + BGE-reranker-v2 (MIT, dense+sparse+multi-vector in 1 Modell).
- OCR-frei/visuell: Qwen3-VL-Embedding oder ColQwen/ColPali (Seiten-Bilder direkt einbetten, ViDoRe).
- Ausgeschlossen: NV-Embed-v2 (CC-BY-NC, nicht-kommerziell).

### 3.6 Infrastruktur (Entscheidungen)
- **Betrieb:** Kernservices always-on, Rest on-demand über Compose-Profile.
- **Vektor-DB:** **Qdrant** (schlank, dense + sparse).
- **Multi-Arch:** `base` + Arch-Override (arm64 zuerst, x86 später).
- **Build:** erst Community-/NVIDIA-Prebuilts, später gepinnte Eigen-Builds.
- **Serving:** vLLM (Arbeitspferd), LiteLLM (Gateway), optional llama-swap
  (Modell-Tausch), SGLang/Ollama/llama.cpp als Optionen.

## 4. Aktueller Stand

**→ Siehe Abschnitt 0 (Update 02.07.2026) für den tagesaktuellen Stand.**

- Repo-Gerüst (`ai-stack/`) steht; Qwen3.6-27B + llm-fast + TTS + STT sind umgesetzt.
- Schritt 1 (llm-fast) ✅ · Schritt 2a (TTS) ✅ · Schritt 2b (STT) ✅ · **Schritt 3 (RAG) = als Nächstes**.

## 5. Repo-Struktur & Funktionsweise

```
ai-stack/
├── .env(.example)     # alle Werte (Token, Images, Modell-IDs, Ports, Tuning)
├── Makefile           # Abkürzungen (make up / up-voice / up-rag); optional
├── compose/
│   ├── base.yml       # arch-agnostischer Service-Graph (Ports, Volumes, Profile)
│   ├── arm64.yml      # DGX-Spark-Override: enthält die vLLM-`command`s + sm_121-Tuning
│   └── x86.yml        # x86-Override (Phase 2)
├── gateway/litellm-config.yaml   # ein Endpoint → alle Backends
├── services/{llm,stt,tts,embedding,ocr}/   # je Runbook
├── infra/{vectordb,proxy,monitoring}/
└── docs/{spark-setup,memory-budget,x86-migration}.md
```

**Wie es zusammenspielt:**
- `.env` enthält `COMPOSE_FILE=compose/base.yml:compose/arm64.yml` → `docker compose`
  mergt beide automatisch. Für x86 später auf `compose/base.yml:compose/x86.yml` ändern.
- **Core-Services** (gateway, qdrant, llm) haben kein Profil → starten immer.
  **On-demand** (stt, tts = Profil `voice`; embedding, ocr = Profil `rag`) starten
  nur mit `--profile voice` / `--profile rag`.
- Das vLLM-`command` (mit allen Flags) liegt im **Arch-Override** (`arm64.yml`), weil
  Quant-Backend/Flags architekturabhängig sind.
- Alle Modelle teilen sich die 128 GB → `gpu-memory-utilization` je Dienst tunen,
  Summe aller gleichzeitig laufenden Dienste **≤ ~0.85** halten (darüber thrasht der
  Unified Memory).

## 6. Funktionierende Konfiguration (Qwen3.6-27B) — korrigiert 02.07.2026

In `.env` gesetzt (die maßgebliche Quelle ist die `.env` selbst, inkl. Kommentaren):
```
VLLM_IMAGE=nvcr.io/nvidia/vllm:26.04-py3       # 26.06 NICHT nehmen (500er-Bug, s. Abschnitt 0)
# lokaler Snapshot-Pfad statt Repo-ID (upstream-Gewichte geändert, s. Abschnitt 0):
LLM_MODEL_ID=/root/.cache/huggingface/hub/models--unsloth--Qwen3.6-27B-NVFP4/snapshots/6db17837...
LLM_TOKENIZER=Qwen/Qwen3.6-27B                 # erprobt mit der unsloth-NVFP4-Variante
LLM_SERVED_NAME=qwen3.6-27b
LLM_GPU_MEM_UTIL=0.50                          # bei 2 LLMs always-on auf ~0.35 senken
LLM_MAX_LEN=32768
LLM_KV_DTYPE=auto
LLM_MAX_SEQS=4
LLM_EXTRA_ARGS=--trust-remote-code
HF_HOME=/srv/docker/ai-stack-2/vllm/models/hf-cache   # geteilter Cache des alten Setups
```
Das vLLM-command steht als volles `vllm serve ...` in `compose/arm64.yml`
(nvcr-Image hat keinen Entrypoint) inkl. Tool-/Reasoning-Parser (qwen3_coder/qwen3).
Start: `make up` bzw. `docker compose up -d llm` → Logs bis "Application startup complete".
Test: `curl http://localhost:8000/v1/models` bzw. Chat über `http://localhost:4000` (Gateway, mit `LITELLM_MASTER_KEY`).

## 7. DGX-Spark-Gotchas (kritisch — im Gerüst bereits berücksichtigt)

- **Kein amd64-`:latest`** — auf aarch64 gibt das "exec format error". Nur
  aarch64/sm_121-Images verwenden (für Produktion per `@sha256:`-Digest pinnen).
- **CUDA 13 als Basis** (sm_121 braucht ≥ 12.9, sonst irreführende FlashInfer-Fehler).
- An **`0.0.0.0`** binden (nicht localhost), sonst greift das Port-Mapping ins Leere.
- **`ipc: host`** (großer /dev/shm für vLLM).
- GPU via `deploy.resources.reservations.devices` + `NVIDIA_VISIBLE_DEVICES=all`.
- **Unified Memory:** `gpu-memory-utilization` konservativ; bei Startup-OOM
  `--enforce-eager` ergänzen und `max-model-len` senken. NVFP4 bevorzugen.
- **Audio-Wheels** (torchaudio, ctranslate2, flash-attn) sind auf aarch64 heikel →
  fertige Community-Server nutzen (siehe Schritt 2).
- **Große Modelle vor dem Start herunterladen** (`huggingface-cli download …`) statt
  beim ersten Container-Start — Fortschritt ist so sichtbar und Abbrüche leichter zu debuggen.

---

## 8. Nächste Schritte (step by step)

### Schritt 1 — "llm-fast" hinzufügen: Qwen3.6-35B-A3B (MoE, 3B aktiv) — ✅ ERLEDIGT 02.07.

> Umgesetzt mit `unsloth/Qwen3.6-35B-A3B-NVFP4` (lokal gecacht & erprobt) statt RedHatAI,
> als Compose-Profil `fast` (on-demand via `make up-fast`, nicht always-on).
> Details unten sind als Referenz erhalten, die tatsächliche Config steht in .env/compose.

Modell: **`RedHatAI/Qwen3.6-35B-A3B-NVFP4`** — NVFP4 im **compressed-tensors**-Format
(gleicher Weg wie der laufende 27B), auf DGX Spark getestet, mit eingebautem MTP-Kopf
für schnelles Speculative Decoding (~167 ms TTFT gemessen). Läuft mit demselben Image
`vllm/vllm-openai:cu130-nightly`.

> Hinweis: NICHT `nvidia/Qwen3.6-35B-A3B-NVFP4` nehmen — die modelopt-Variante hat auf
> dem Spark ein `lm_head.input_scale`-Ladeproblem. Die RedHatAI-Variante lädt sauber.

**(a) Modell vorab laden** (auf dem Spark):
```
huggingface-cli download RedHatAI/Qwen3.6-35B-A3B-NVFP4 \
  --local-dir-use-symlinks False
```

**(b) `.env` ergänzen** (beide LLMs always-on → Utilization je senken, Summe ≤ ~0.85):
```
# 27B von 0.50 auf 0.30 senken, damit beide LLMs koexistieren:
LLM_GPU_MEM_UTIL=0.30

# llm-fast:
LLM_FAST_MODEL_ID=RedHatAI/Qwen3.6-35B-A3B-NVFP4
LLM_FAST_SERVED_NAME=qwen3.6-35b-fast
LLM_FAST_PORT=8001
LLM_FAST_GPU_MEM_UTIL=0.30
LLM_FAST_MAX_LEN=40960
```

**(c) Service in `compose/base.yml` hinzufügen** (unter den `llm`-Block, gleiche Struktur):
```yaml
  llm-fast:
    image: ${VLLM_IMAGE}
    container_name: ai-llm-fast
    restart: unless-stopped
    # command -> compose/arm64.yml
    ports:
      - "${LLM_FAST_PORT}:8000"
    environment:
      HF_TOKEN: ${HF_TOKEN}
      HUGGING_FACE_HUB_TOKEN: ${HF_TOKEN}
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: compute,utility
    volumes:
      - ${HF_HOME}:/root/.cache/huggingface
    ipc: host
    networks: [aistack]
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 300s
```

**(d) `command` in `compose/arm64.yml` hinzufügen:**
```yaml
  llm-fast:
    platform: linux/arm64
    command:
      - "--model=${LLM_FAST_MODEL_ID}"
      - "--served-model-name=${LLM_FAST_SERVED_NAME}"
      - "--host=0.0.0.0"
      - "--port=8000"
      - "--gpu-memory-utilization=${LLM_FAST_GPU_MEM_UTIL}"
      - "--max-model-len=${LLM_FAST_MAX_LEN}"
      - "--kv-cache-dtype=fp8"
      - "--reasoning-parser=qwen3"
      - "--enable-auto-tool-choice"
      - "--tool-call-parser=qwen3_coder"
      - "--enable-prefix-caching"
      - "--limit-mm-per-prompt"
      - "image=0"
      - "--trust-remote-code"
      # Optional für mehr Speed (eingebauter MTP-Kopf) — bei Fehlern weglassen:
      # - "--speculative-config"
      # - '{"method":"mtp","num_speculative_tokens":2}'
```

**(e) In `gateway/litellm-config.yaml` unter `model_list` ergänzen:**
```yaml
  - model_name: qwen3.6-35b-fast
    litellm_params:
      model: openai/qwen3.6-35b-fast
      api_base: http://llm-fast:8000/v1
      api_key: dummy
```

**(f) Hochfahren & testen:**
```
docker compose up -d llm-fast          # lädt/startet den Fast-Service
docker compose logs -f llm-fast        # bis "startup complete"
docker compose up -d                   # Gateway zieht das neue Modell mit hoch
curl http://localhost:4000/v1/models   # sollte qwen3.6-27b UND qwen3.6-35b-fast zeigen
```
Ergebnis: Clients wählen per `model`-Feld — `qwen3.6-27b` (Qualität) oder
`qwen3.6-35b-fast` (Geschwindigkeit). Beide teilen sich die 128 GB (2× ~0.30 = ~0.60,
Rest bleibt für Voice/RAG on-demand).

> Alternative: llm-fast statt always-on nur bei Bedarf laden → `profiles: ["fast"]`
> in base.yml ergänzen und mit `docker compose --profile fast up -d` starten.

### Schritt 2 — Voice-Profil: Qwen3-ASR (STT) + Qwen3-TTS (TTS) — ✅ KOMPLETT 02.07.

> **TTS läuft:** `make up-tts`, Port 8002, Modell `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`
> über `martinb78/faster-qwen3-tts-dgx-spark` (DE/EN getestet, ~2.4× Echtzeit).
> Setup/Stimmen: `services/tts/README.md`.
> **STT läuft:** `make up-stt`, Port 8003, Modell `Qwen/Qwen3-ASR-0.6B` über
> `ghcr.io/aeon-7/qwen3-asr-server` (DE/EN getestet, direkt + Gateway).
> Details/Gotchas: Abschnitt 0 (Session 3) + `services/stt/README.md`.

Ziel: `make up-voice` startet STT + TTS als OpenAI-kompatible Audio-Endpoints.
- **STT:** Qwen3-ASR-0.6B → `/v1/audio/transcriptions`. Basis: `AEON-7/qwen3-asr-server`
  (vLLM-nativ, sm_121, löst die aarch64-Audio-Wheels bereits).
- **TTS:** Qwen3-TTS-0.6B → `/v1/audio/speech`. Basis: `AEON-7/qwen3-tts-server` oder
  `mARTin-B78/dgx-spark-faster-qwen3-tts` (CUDA-Graph, mehrere Voice-Backends).
- Umsetzung: entweder deren Images als `STT_IMAGE`/`TTS_IMAGE` in `.env` setzen, oder
  `Dockerfile` in `services/stt` bzw. `services/tts` ablegen und `build:` per Override.
- Danach die auskommentierten `qwen3-asr`/`qwen3-tts`-Blöcke in `litellm-config.yaml`
  aktivieren (oder Dienste direkt unter `http://stt:8000` / `http://tts:8000` ansprechen).
- Speicher: sind klein (~2–3 GB je), passen zusätzlich in die 128 GB.

### Schritt 3 — RAG-Profil: Qwen3-Embedding + Reranker + Qdrant + Docling/OCR

Ziel: `make up-rag`.
- **Embedding:** läuft über dasselbe vLLM-Image mit `--task embed` (command steht schon
  in `arm64.yml`), hinter LiteLLM als `qwen3-embedding`. `EMBED_MODEL_ID` in `.env`.
- **Reranker:** zweiter vLLM-Dienst (`--task score`), Qwen3-Reranker.
- **Qdrant** läuft bereits als Core-Service (:6333).
- **OCR:** Docling-serve + Erkennung. **De-risk-Reihenfolge:** zuerst Granite-Docling-258M
  (Apache 2.0, via vLLM/transformers, Latein-Schrift), PaddleOCR-VL nachziehen (braucht
  onnxruntime-gpu für sm_121 — Referenz: `HendrikSchoettle/ragflow-dgx-spark`).
- **RAG-Fluss:** Dokument → Docling → Chunks → Embedding → Qdrant → Retrieval → Reranker → LLM.

### Schritt 4 — Härtung
- Reverse Proxy mit TLS (Traefik/Caddy) vor die Dienste.
- Monitoring: Prometheus + Grafana + GB10-Unified-Memory-Exporter.
- Images per `@sha256:`-Digest pinnen; ggf. eigene sm_121-Images via GitHub Actions bauen.
- Non-root-User mit Host-UID in den Containern (Bind-Mount-Ownership + Sicherheit).

### Schritt 5 — Portierung nach x86
- In `.env`: `COMPOSE_FILE=compose/base.yml:compose/x86.yml`, `VLLM_IMAGE` auf ein
  Standard-amd64-Image (z. B. `vllm/vllm-openai:<version>`).
- Service-Graph, Qdrant, LiteLLM-Config, App-Code bleiben identisch.
- Für eigene Images `docker buildx --platform linux/amd64,linux/arm64` → ein Tag für beide.

## 9. Referenzen (DGX Spark)

- `NVIDIA/dgx-spark-playbooks` — offizielle Playbooks
- `bidual/awesome-dgx-spark` — kuratierte Liste
- Modell-Recipes: `recipes.vllm.ai/Qwen/Qwen3.6-35B-A3B`, `vllm.ai/blog` (Spark)
- vLLM-Images: `vllm/vllm-openai:cu130-nightly`, `hellohal2064/vllm-dgx-spark-gb10`,
  `scitrera/dgx-spark-vllm`, `eugr/spark-vllm-docker`
- Audio-Server: `AEON-7/qwen3-asr-server`, `AEON-7/qwen3-tts-server`
- Modelle: `ocicek/Qwen3.6-27B-NVFP4`, `RedHatAI/Qwen3.6-35B-A3B-NVFP4`,
  `Qwen/Qwen3.6-35B-A3B-FP8` (offizielle FP8-Alternative)

## 10. Startprompt für die neue Konversation (Vorschlag)

> "Ich baue einen selbstgehosteten AI-Stack auf einem DGX Spark (GB10, ARM/sm_121).
> Das beigefügte Dokument beschreibt den kompletten Kontext, die Modellauswahl, den
> aktuellen Stand (Qwen3.6-27B läuft über vLLM) und die nächsten Schritte. Bitte lies es
> und lass uns bei **Schritt 1** weitermachen: das llm-fast-Modell (Qwen3.6-35B-A3B)
> hinzufügen. Ich bin kein Docker-/YAML-Experte — bitte führ mich schrittweise und
> erkläre knapp, was jede Aktion tut."
