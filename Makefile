.PHONY: run build test lint docker-build docker-up docker-down clean

APP     := go-api
BIN_DIR := bin
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

run:
	ENV=development APP_VERSION=$(VERSION) go run ./cmd/server

build:
	CGO_ENABLED=0 go build -ldflags="-w -s" -o $(BIN_DIR)/$(APP) ./cmd/server

test:
	go test -v -race ./...

test-cover:
	go test -race -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "coverage report: coverage.html"

lint:
	@which golangci-lint > /dev/null || (echo "install golangci-lint first: https://golangci-lint.run/usage/install/" && exit 1)
	golangci-lint run ./...

docker-build:
	docker build --build-arg APP_VERSION=$(VERSION) -t $(APP):$(VERSION) .

docker-up:
	docker compose -f infra/docker-compose.yml up -d --build

docker-down:
	docker compose -f infra/docker-compose.yml down

docker-logs:
	docker compose -f infra/docker-compose.yml logs -f app

clean:
	rm -rf $(BIN_DIR) coverage.out coverage.html
