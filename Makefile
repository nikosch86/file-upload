.PHONY: help test test-e2e build up down clean

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk -F':.*?##' '{printf "  %-12s %s\n", $$1, $$2}'

test: test-e2e  ## Run all tests

test-e2e:  ## Run end-to-end tests against an isolated docker compose stack
	@bash tests/e2e.sh

build:  ## Build production images
	docker compose build

up:  ## Start the production stack in the background
	docker compose up -d

down:  ## Stop the production stack
	docker compose down

clean:  ## Stop the production stack and remove volumes
	docker compose down -v
