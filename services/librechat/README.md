# LibreChat — Chat-UI des Stacks (Core, CPU-only)

Browser-Front-end für alle Dienste: Chat (27B / llm-fast), Vorlesen (TTS),
Diktieren (STT) — alles über das Gateway (`http://gateway:4000/v1`).
Host: `http://<spark-ip>:3080`. Start: `make up` (Teil des Core) oder
`make up-ui` (nur UI + MongoDB, ohne GPU-Dienste).

## Warum LibreChat (Session-4-Entscheidung)

Pures **MIT** — Open WebUI steht seit v0.6.6 (04/2025) unter Custom-Lizenz
mit Branding-Klausel (>50 User) und ist nicht mehr OSI-konform. LibreChat
darf vollständig rebrandet/produktisiert werden. Seit 11/2025 gehört das
Projekt ClickHouse (öffentliche MIT-Zusage). Nuance: die Pflicht-Dependency
MongoDB ist SSPL (interne Nutzung unkritisch).

**Bewusst NICHT übernommen:** `rag_api` + pgvector + Meilisearch aus dem
Upstream-Compose. LibreChats RAG ist naiv (Fixed-Chunks, dense-only, kein
Reranker/Hybrid, OCR-Default = Mistral-Cloud). Unser RAG kommt als eigener
MCP-Retrieval-Server (Qdrant + Embedding + Reranker + lokales OCR) und wird
über `mcpServers` in `librechat.yaml` an Agents angebunden (Schritt 3).

## Konfiguration

- `librechat.yaml` (dieses Verzeichnis, read-only gemountet nach
  `/app/librechat.yaml`): Custom Endpoint „AI-Stack" → Gateway, `speech:`-Block
  für STT/TTS. `${LITELLM_MASTER_KEY}` wird gegen die Container-Env aufgelöst.
- Secrets (`LIBRECHAT_JWT_SECRET`, `..._JWT_REFRESH_SECRET`, `..._CREDS_KEY`,
  `..._CREDS_IV`) in `.env` — Generierung siehe `.env.example`.
- `models.fetch: false` mit expliziter Modell-Liste: `/v1/models` am Gateway
  listet auch `qwen3-tts`/`qwen3-asr`, die nicht ins Chat-Dropdown gehören.
  Neue Chat-Modelle ⇒ in `librechat.yaml` UND `gateway/litellm-config.yaml`
  eintragen.

## Erststart

1. `make up` (bzw. `make up-voice` für Sprachdialog)
2. `http://<spark-ip>:3080` öffnen → **ersten Account registrieren**
   (`ALLOW_REGISTRATION=true`; vor LAN-Freigabe abwägen, siehe HOW-TO.md)
3. Modell „AI-Stack → qwen3.6-27b" wählen, chatten
4. Sprachdialog: Einstellungen → Sprache — **Engine bei STT und TTS auf
   „External" stellen** (einmalig pro Browser/Profil; Default „Browser" =
   Web-Speech-API des Browsers, nicht unser Stack — siehe unten),
   Voice aus `services/tts/customvoice_voices.json` (z. B. `serena-de`);
   die Modelle `qwen3-asr`/`qwen3-tts` kommen aus `librechat.yaml`

## Bekanntes Verhalten: TTS liest den Think-Block mit vor

**Entscheidung Session 5 (07.07.2026):** LibreChats Vorlese-Funktion liest
bei Reasoning-Modellen den Think-Block mit vor. Die Ursachen sind komplett
diagnostiziert (5 Upstream-Bugs, Details unten), ein funktionierender
Patch-Satz wurde gebaut und serverseitig E2E-verifiziert — dann aber
**bewusst wieder entfernt** (4 an v0.8.7 gebundene Dateikopien = zu viel
Wartungslast; Browser-Cache-Schichten machten das Ausrollen zäh).
**Der komplette Patch-Satz inkl. Doku liegt in Commit `7dcd90c`**
(`services/librechat/patches/`), falls er reaktiviert werden soll.
Geplanter sauberer Weg: dünner TTS-Proxy-Service zwischen LibreChat und
Gateway, der den Think-Anteil filtert — unabhängig von LibreChat-Interna.

Diagnostizierte Upstream-Bugs (Stand 07/2026 auch auf `main`; Issue/PR-Paket
wert: danny-avila/LibreChat):
1. `streamAudio.js` (Server, Streaming-Route der automatischen Wiedergabe):
   skipReasoning-Default falsch UND der geparste Text wird nicht verwendet.
2. Klick-Vorlesen geht IMMER über `POST /tts/manual` mit **client-seitig**
   gebautem Text inkl. Think (`parseTextParts`-Default; der TTS-Cache-Toggle
   wechselt NICHT die Route, er steuert nur die CacheStorage).
3. Alte CacheStorage-Einträge (`tts-responses`) überleben Hard-Reloads
   (bei Audio-Altlasten: DevTools → Application → Cache Storage löschen).
4. **Default-Engine `browser` für TTS UND STT** (Web Speech API, rein
   client-seitig: liest Roh-Text inkl. Think, bricht bei langen Texten ab,
   kein Server-Request). Jeder User muss einmalig „External" wählen.
5. Ein External-Default per `speech.speechTab` in librechat.yaml ist in
   v0.8.7 unmöglich: Schema-Enum (`openai/azureOpenAI/…`) passt nicht zu
   den Client-Werten (`browser/external`), der Client resettet unbekannte
   Werte auf `browser` („Resetting invalid TTS engine").

## Betrieb

- MongoDB (`ai-mongodb`) läuft ohne Auth, **ohne Host-Port** — nur im
  Compose-Netz erreichbar. User/Chats liegen im Volume `mongo-data`.
- Uploads/Bilder/Logs: Volumes `librechat-uploads`/`-images`/`-logs`.
- Suche ist aus (`SEARCH=false`, kein Meilisearch); bei Bedarf später als
  Service ergänzen.
- llm-fast (`qwen3.6-35b-fast`) ist on-demand: solange nicht gestartet
  (`make up-fast`), schlagen nur Anfragen an dieses Modell fehl.
