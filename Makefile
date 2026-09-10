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
	PGPASSWORD=mayak psql -h localhost -p 5433 -U mayak -d mayak

redis:
	redis-cli -p 6380
