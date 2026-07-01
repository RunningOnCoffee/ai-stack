# OCR — Docling + PaddleOCR-VL (on-demand, Profil `rag`)  [GEPLANT]

Docling (MIT) als Pipeline (PDF/DOCX/… → Markdown/JSON/DocTags, Layout/Tabellen,
RAG-Chunking), PaddleOCR-VL (109 Sprachen) als Erkennung. Start: `make up-rag`.

## aarch64-Hinweis
PaddleOCR-VL braucht onnxruntime-gpu für sm_121 — Referenz: `HendrikSchoettle/ragflow-dgx-spark`
liefert einen quellgebauten Wheel. **De-risk:** zuerst Granite-Docling-258M
(Apache 2.0, via vLLM/transformers, Latein-Schrift = DE/EN) fahren, PaddleOCR-VL
nachziehen, sobald validiert.

## Fluss
Dokument → Docling → Chunks → Embedding-Dienst → Qdrant.
