# =============================================================================
#  Lineage 2 Interlude x10 — управление стендом.
#  make            — список команд
#  make install    — установка с нуля одной командой
# =============================================================================

SHELL := /bin/bash

# -f указан явно намеренно: если в окружении задана переменная COMPOSE_FILE
# (частая история на рабочих машинах, где крутится другой стек), она
# перебивает выбор файла в любом каталоге. Явный путь исключает
# ситуацию, когда 'make down' гасит чужие контейнеры.
COMPOSE := docker compose -f docker-compose.yml

.DEFAULT_GOAL := help
.PHONY: help install env build configure db-init up down stop start restart \
        logs logs-login logs-db status client play gm online backup restore test clean clean-all

help:
	@echo ""
	@echo "  Установка"
	@echo "    make install     полная установка: сборка + конфиги + база + запуск"
	@echo "    make env         создать .env из шаблона"
	@echo "    make build       скачать и собрать эмулятор в ./dist"
	@echo "    make configure   применить профиль рейтов и сетевые настройки"
	@echo "    make db-init     создать и наполнить базы (СТИРАЕТ данные)"
	@echo ""
	@echo "  Работа"
	@echo "    make up          запустить сервер"
	@echo "    make down        остановить и удалить контейнеры"
	@echo "    make restart     перезапустить игровой и логин-сервер"
	@echo "    make status      состояние: контейнеры, порты, онлайн, GC"
	@echo "    make logs        логи игрового сервера (Ctrl+C для выхода)"
	@echo "    make logs-login  логи логин-сервера"
	@echo "    make logs-db     логи базы"
	@echo ""
	@echo "  Клиент игры"
	@echo "    make client DIR=~/l2-client   прописать адрес сервера в клиент"
	@echo "    make play                     запустить клиент через Wine"
	@echo ""
	@echo "  Администрирование"
	@echo "    make gm CHAR=Имя     выдать права ГМ персонажу"
	@echo "    make online          кто сейчас в игре"
	@echo "    make backup          резервная копия баз"
	@echo "    make restore FILE=x  восстановить из копии"
	@echo ""
	@echo "  Разработка"
	@echo "    make test        прогнать тесты скриптов стенда"
	@echo "    make clean       удалить собранную сборку (./dist)"
	@echo "    make clean-all   удалить сборку, исходники и тома с данными"
	@echo ""

env:
	@if [ -f .env ]; then \
		echo "  .env уже есть — не трогаю"; \
	else \
		cp .env.example .env; \
		echo "  создан .env — открой его и поменяй пароли и L2_EXTERNAL_IP"; \
	fi

install: env
	@echo "==> установка с нуля"
	@$(MAKE) --no-print-directory build
	@$(MAKE) --no-print-directory configure
	@$(MAKE) --no-print-directory db-init
	@$(MAKE) --no-print-directory up
	@echo ""
	@echo "  Готово. Дальше — docs/CLIENT-SETUP.md: настройка клиента игры."

build:
	@./scripts/build-server.sh

configure:
	@./scripts/configure.sh

db-init:
	@./scripts/db-setup.sh

up:
	@$(COMPOSE) up -d
	@echo ""
	@./scripts/status.sh

down:
	@$(COMPOSE) down

stop:
	@$(COMPOSE) stop

start:
	@$(COMPOSE) start

# Игровой сервер сохраняет персонажей при остановке, поэтому даём ему время.
restart:
	@$(COMPOSE) restart --timeout 60 login game

logs:
	@$(COMPOSE) logs -f --tail 200 game

logs-login:
	@$(COMPOSE) logs -f --tail 200 login

logs-db:
	@$(COMPOSE) logs -f --tail 200 db

status:
	@./scripts/status.sh

client:
	@if [ -z "$(DIR)" ]; then ./scripts/client.sh setup; \
	else ./scripts/client.sh setup "$(DIR)"; fi

play:
	@./scripts/client.sh run

gm:
	@if [ -z "$(CHAR)" ]; then \
		echo "  укажи персонажа:  make gm CHAR=ИмяПерсонажа"; exit 1; fi
	@./scripts/account.sh gm "$(CHAR)" $(LEVEL)

online:
	@./scripts/account.sh online

backup:
	@./scripts/backup.sh

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "  укажи файл:  make restore FILE=backups/l2-....sql.gz"; exit 1; fi
	@./scripts/backup.sh --restore "$(FILE)"

test:
	@./scripts/tests/run-tests.sh

clean:
	@rm -rf dist
	@echo "  ./dist удалён. Пересобрать:  make build"

clean-all: down
	@rm -rf dist .sources logs
	@$(COMPOSE) down -v
	@echo "  удалено всё, включая базу данных и скачанные исходники"
