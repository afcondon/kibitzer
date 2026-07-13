# kibitzer — build orchestration

PORT ?= 3077

.PHONY: help bootstrap build test example bundle serve clean

help:
	@echo "kibitzer targets:"
	@echo "  bootstrap  npm install (http-server for make serve)"
	@echo "  build      spago build (all workspace packages)"
	@echo "  test       run the kibitzer-core test suite"
	@echo "  example    run the CLI transcript demo (SEED=42 to override)"
	@echo "  bundle     bundle the frontend to frontend/public/bundle.js"
	@echo "  serve      serve the frontend on http://localhost:$(PORT)"
	@echo "  clean      remove build output"

bootstrap:
	npm install

build:
	spago build

test:
	spago test -p kibitzer-core

SEED ?= 42
example:
	spago run -p kibitzer-example -- $(SEED)

bundle:
	spago bundle -p kibitzer-frontend

serve:
	npx http-server frontend/public -p $(PORT) -c-1 --cors

clean:
	rm -rf output .spago frontend/public/bundle.js
