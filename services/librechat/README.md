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
   Web-Speech-API des Browsers, nicht unser Stack — siehe Patches-Abschnitt),
   Voice aus `services/tts/customvoice_voices.json` (z. B. `serena-de`);
   die Modelle `qwen3-asr`/`qwen3-tts` kommen aus `librechat.yaml`

## Patches (an die Image-Version v0.8.7 gebunden!)

Zwei ro-Mounts (compose/base.yml) legen sich über Original-Dateien im Image,
damit TTS **nicht den Reasoning-/Think-Block vorliest**. Hintergrund: Es gibt
zwei getrennte TTS-Pfade, beide hatten denselben Bug (skipReasoning-Default
fälschlich `false`):

1. **`patches/streamAudio.js`** (Server) — Streaming-Route
   `POST /api/files/speech/tts`, genutzt NUR von der automatischen
   Wiedergabe (`automaticPlayback`, Vorlesen während der Generierung).
   Zwei Fixes: (a) `parseTextParts(..., true)` (= skipReasoning);
   (b) der geparste Text wird jetzt wirklich verwendet — upstream wurde er
   nur gecacht und danach wieder das rohe `message.text` gelesen.
2. **`patches/hooks.Bi3Cm4Qy.js`** (Client-Bundle, minifiziert) — der
   **Klick auf den Vorlese-Button** geht IMMER über `POST /tts/manual`
   mit **client-seitig** gebautem Text (Session-5-Erkenntnis: der
   TTS-Cache-Toggle wechselt NICHT die Route, er steuert nur, ob die
   CacheStorage `tts-responses` gelesen/befüllt wird — die Session-4-Notiz
   „Cache AN = Streaming-Route" war falsch). Patch = 1 Byte: im Text-Parser
   `function by(e,t=!1)` → `t=!0` (skipReasoning-Default true; `by` =
   minifiziertes `parseTextParts`). Nebeneffekt: Cache-Keys sind der
   Text selbst → alte Think-Audios matchen nach dem Patch nicht mehr.
3. **`patches/sw.js`** — nötig, damit Patch 2 Browser mit bereits
   installiertem Service Worker überhaupt erreicht: das Workbox-Precache-
   Manifest führt `hooks.Bi3Cm4Qy.js` mit `revision:null`, d. h. der SW
   refetcht die Datei bei gleichem Namen NIE (übersteht auch Hard-Reloads).
   Patch = Revision-Bump auf `"think-patch-1"` für genau diesen Eintrag →
   der SW lädt das Bundle beim nächsten normalen Seitenaufruf neu.
   (Bei künftigen Patch-Änderungen am Bundle: Revision erneut bumpen.)
4. **`patches/TTSService.js`** (Server) — **der eigentliche Backstop**,
   wirkt unabhängig von allen Browser-/SW-/HTTP-Cache-Schichten: die
   manuelle Route `/tts/manual` filtert den Client-Input serverseitig.
   (a) Exakt-Abgleich gegen die letzten 25 Assistant-Nachrichten des Users:
   Input == `parseTextParts(content, false)` (Think+Antwort, wie ihn
   Alt-Clients mit gecachtem Bundle senden — OHNE `<think>`-Tags!) →
   ersetzt durch `parseTextParts(content, true)` (nur die Antwort);
   deterministisch, keine False Positives. (b) Fallback: rohe
   `<think>`/`<thinking>`-Tag-Blöcke werden per Regex entfernt.
   E2E getestet (Tag-Variante: 230-Zeichen-Input → 3,25 s Audio = nur der
   Antwortsatz). **Toggle:** `TTS_READ_THINK=true` in der `.env` schaltet
   den Filter ab (Default: aktiv).

Upstream-Bugs (Stand 07/2026 auch auf `main`; Issue/PR-Paket wert:
danny-avila/LibreChat): die zwei streamAudio-Bugs (oben 1a/1b), der
Klick-Parser ohne skipReasoning (oben 2), dazu ungepatcht: alte
CacheStorage-Einträge überleben Hard-Reload (bei Audio-Altlasten einmalig
DevTools → Application → Cache Storage → `tts-responses` löschen) und
**Default-Engine `browser` für TTS UND STT** (Web Speech API, rein
client-seitig: liest Roh-Text inkl. Think, bricht bei langen Texten ab,
kein Server-Request — Ursache des Session-4-Mysterys „Think trotz Patch").
Jeder User muss einmalig Engine „External" wählen (Erststart Schritt 4);
ein External-Default per `speech.speechTab` in librechat.yaml ist in
v0.8.7 **unmöglich**: Schema-Enum (`openai/azureOpenAI/…`) passt nicht zu
den Client-Werten (`browser/external`), der Client resettet unbekannte
Werte auf `browser` („Resetting invalid TTS engine").
**Beim Image-Update:** Dateien neu aus dem Image kopieren, Patches neu
anwenden (oder prüfen, ob upstream gefixt → Mounts entfernen). Der
Bundle-Dateiname (`hooks.Bi3Cm4Qy.js`) ändert sich mit jedem Build —
dann läuft der Mount ins Leere und der Bug ist zurück.

## Betrieb

- MongoDB (`ai-mongodb`) läuft ohne Auth, **ohne Host-Port** — nur im
  Compose-Netz erreichbar. User/Chats liegen im Volume `mongo-data`.
- Uploads/Bilder/Logs: Volumes `librechat-uploads`/`-images`/`-logs`.
- Suche ist aus (`SEARCH=false`, kein Meilisearch); bei Bedarf später als
  Service ergänzen.
- llm-fast (`qwen3.6-35b-fast`) ist on-demand: solange nicht gestartet
  (`make up-fast`), schlagen nur Anfragen an dieses Modell fehl.
