COMPOSE := docker compose -f deploy/docker-compose.yml

.PHONY: help up down logs run build test fmt vet tidy psql redis reset

help:
	@echo "make up      — поднять Postgres, Redis, MinIO"
	@echo "make down    — остановить инфраструктуру"
	@echo "make run     — запустить сервер (миграции применятся сами)"
	@echo "make test    — прогнать тесты (нужен make up)"
	@echo "make fmt     — gofmt по коду сервера"
	@echo "make reset   — снести данные и поднять инфраструктуру заново"

up:
	$(COMPOSE) up -d --wait

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

reset:
	$(COMPOSE) down -v
	$(COMPOSE) up -d --wait

run:
	cd server && go run ./cmd/api

build:
	cd server && go build -o bin/api ./cmd/api

test:
	cd server && go test ./... -count=1

fmt:
	cd server && gofmt -w .

vet:
	cd server && go vet ./...

tidy:
	cd server && go mod tidy

psql:
	PGPASSWORD=tito psql -h localhost -p 5433 -U tito -d tito

redis:
	redis-cli -p 6380

# --- Клиент ---

.PHONY: app-get app-gen app-test app-analyze app-web app-icon e2e e2e-web shots web-dev web-build web-test

app-get:
	cd app && flutter pub get

app-gen:
	cd app && dart run build_runner build --delete-conflicting-outputs

app-analyze:
	cd app && flutter analyze

app-test:
	cd app && flutter test

app-web:
	cd app && flutter build web --release --dart-define=TITO_API=$(or $(API),http://localhost:8080)

# Знак приложения: перерисовать из темы и разложить по платформам.
# Нужен Pillow: pip install Pillow
app-icon:
	cd app && python3 tool/generate_icon.py && dart run flutter_launcher_icons

# Сквозная проверка: живой клиент против живого сервера. Подробности в e2e/README.md
e2e:
	cd e2e && npm install --silent && node chat.mjs

e2e-web:
	cd e2e && npm install --silent && node web.mjs

# Все экраны обоих клиентов одной картинкой. Нужны поднятые сервер,
# веб-клиент на 4173 и сборка Flutter web на 8090 — см. e2e/README.md.
#
#   make shots ONLY=web       — только веб-клиент
#   make shots ONLY=flutter   — только Flutter
shots:
	cd e2e && npm install --silent && node shots.mjs $(if $(ONLY),--only=$(ONLY),)
	python3 e2e/sheet.py
	python3 e2e/palette.py

web-dev:
	cd web && npm install --silent && npm run dev

web-build:
	cd web && npm install --silent && VITE_API_BASE=$(or $(API),http://localhost:8080) npm run build

web-test:
	cd web && npm install --silent && npm run typecheck
