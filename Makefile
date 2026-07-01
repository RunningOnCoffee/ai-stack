# Bequeme Wrapper um docker compose.
# COMPOSE_FILE kommt aus .env (merged base + Arch-Override).
# '>' statt Tab als Recipe-Prefix (GNU Make >= 3.82).
.RECIPEPREFIX = >
.PHONY: help up up-voice up-rag up-full down logs ps pull restart pin-check

help:
> @echo "up        Core-Services (LiteLLM, Qdrant, LLM) starten"
> @echo "up-voice  + Voice-Profil (STT, TTS)"
> @echo "up-rag    + RAG-Profil (Embedding, OCR)"
> @echo "up-full   Core + Voice + RAG"
> @echo "down      alles stoppen"
> @echo "logs      Logs folgen (S=service, z.B. make logs S=llm)"
> @echo "ps        Status"
> @echo "pull      Images ziehen"
> @echo "pin-check warnt vor ungepinnten :latest-Tags in .env"

up:
> docker compose up -d

up-voice:
> docker compose --profile voice up -d

up-rag:
> docker compose --profile rag up -d

up-full:
> docker compose --profile voice --profile rag up -d

down:
> docker compose --profile voice --profile rag down

logs:
> docker compose logs -f $(S)

ps:
> docker compose ps

pull:
> docker compose pull

restart:
> docker compose restart $(S)

pin-check:
> @grep -nE '=(.*):latest' .env && echo "WARN: ungepinnte :latest-Images oben — vor Produktion per @sha256 pinnen." || echo "OK: keine :latest-Tags."
