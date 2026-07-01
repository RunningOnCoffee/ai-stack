# LLM — Qwen3.6-27B (vLLM, Core, always-on)

OpenAI-kompatibler Server, hinter LiteLLM als `qwen3.6-27b` erreichbar.
Definition in `compose/base.yml` (Skeleton) + `compose/arm64.yml` (command/Flags).

## Image pinnen (Spark, sm_121)
Kein amd64-`:latest` (→ "exec format error"). aarch64/sm_121-Image wählen und
in `.env` als `VLLM_IMAGE=...@sha256:<digest>` pinnen. Kandidaten:
- `hellohal2064/vllm-dgx-spark-gb10` (verifiziert mit Qwen3-Embedding/VL)
- `vllm/vllm-openai:cu130-nightly-<commit>` (nightly driftet → Digest pinnen)
- `scitrera/dgx-spark-vllm:<version>-t4` (stabil versioniert)

## Modell-Variante
`LLM_MODEL_ID` auf eine Qwen3.6-27B-Repo setzen — möglichst **NVFP4** (Blackwell-nativ,
kleinster Footprint). FP8 als Alternative. BF16 nur wenn Speicher egal.

## Tuning
- Startet zu groß / OOM? → `LLM_GPU_MEM_UTIL` senken, `--enforce-eager` in
  `LLM_EXTRA_ARGS`, `LLM_MAX_LEN` reduzieren. Siehe `docs/memory-budget.md`.
- Langer Kontext? → `LLM_KV_DTYPE=fp8`.
- Als Doc-VLM nutzen? → `--limit-mm-per-prompt image=0` in arm64.yml auf >0 setzen.

## Test
    curl http://localhost:8000/v1/models
