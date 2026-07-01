# DGX Spark — Setup & aarch64-Gotchas

## 1. System prüfen
    uname -a          # ... aarch64 ...  (bestätigt ARM64)
    nvidia-smi        # Driver + CUDA 13.x, GB10 Grace Blackwell
    docker --version

## 2. GPU-in-Docker testen
    docker run --rm --gpus all nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04 nvidia-smi
Zeigt das die GPU, ist das NVIDIA Container Toolkit ok.

## 3. NGC (optional, für nvcr.io-Images)
ARM64-Variante der NGC-CLI installieren (ARM64-Linux-Tab auf ngc.nvidia.com),
dann `docker login nvcr.io`.

## 4. Das richtige vLLM-Image finden & pinnen
Standard-Docker-Hub-`:latest` ist **amd64** → auf aarch64 "exec format error".
Ein aarch64/sm_121-Image nehmen und in `.env` per Digest pinnen:
    docker pull hellohal2064/vllm-dgx-spark-gb10:latest
    docker inspect --format '{{index .RepoDigests 0}}' hellohal2064/vllm-dgx-spark-gb10:latest
    # -> VLLM_IMAGE=hellohal2064/vllm-dgx-spark-gb10@sha256:...
Alternativen: vllm/vllm-openai:cu130-nightly-<commit>, scitrera/dgx-spark-vllm.

## Gotcha-Checkliste (in den Compose-Dateien bereits berücksichtigt)
- [x] Nur aarch64/sm_121-Images, per Digest gepinnt (kein :latest/amd64)
- [x] CUDA 13 Base (sm_121 braucht >= 12.9, sonst irreführende FlashInfer-Fehler)
- [x] An 0.0.0.0 binden (nicht localhost)
- [x] `ipc: host` (großer /dev/shm für vLLM)
- [x] `--gpus all` via deploy.resources / NVIDIA_VISIBLE_DEVICES=all
- [ ] Non-root-User mit Host-UID (Bind-Mount-Ownership) — Härtung Phase 2
- [ ] Audio-Wheels (torchaudio/ctranslate2/flash-attn) aarch64: Community-Server nutzen
