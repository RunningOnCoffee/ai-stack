# Embedding + Reranker — Qwen3 (on-demand, Profil `rag`)  [GEPLANT]

Läuft über dasselbe vLLM-Image (`--task embed`), hinter LiteLLM als `qwen3-embedding`.
Command steht bereits in `compose/arm64.yml`. Start: `make up-rag`.

## Reranker
Zweite Stufe: Qwen3-Reranker als separater vLLM-Dienst (`--task score`) oder
über die Reranking-API. `RERANK_MODEL_ID` in `.env`.

## Qdrant
Embeddings landen in Qdrant (:6333). Dense + sparse (Hybrid) für exaktes
Entity-Matching. Collection-Setup gehört in den RAG-Ingest (Docling → Chunks → Qdrant).
