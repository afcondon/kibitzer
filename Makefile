# kibitzer — build orchestration

# 3026 is the Bosun-allocated port (fleet.json: kilo-papa-zulu-delta:frontend).
# `bosun serve` lazy-spawns this same command on first request; `make serve`
# is the manual fallback when the router isn't running.
PORT ?= 3026

.PHONY: help bootstrap build test example skylines orbits worlds bettor bettor-validate bundle serve clean

help:
	@echo "kibitzer targets:"
	@echo "  bootstrap  npm install (http-server for make serve)"
	@echo "  build      spago build (all workspace packages)"
	@echo "  test       run the kibitzer-core test suite"
	@echo "  example    run the CLI transcript demo (SEED=42 to override)"
	@echo "  skylines   regenerate frontend/public/skylines.html (small multiples)"
	@echo "  orbits     regenerate frontend/public/orbits.html (radial small multiples)"
	@echo "  worlds     regenerate the Z3 model-space pages (worlds.html, worlds-gap.html)"
	@echo "  bettor     regenerate frontend/public/bettor.html (the EV watcher-watcher; SEED=n)"
	@echo "  bettor-validate  silent-run the bettor over 200 games (slow; feeds the page's table)"
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

skylines:
	spago run --quiet -p kibitzer-example -- skylines > frontend/public/skylines.html

orbits:
	spago run --quiet -p kibitzer-example -- orbits > frontend/public/orbits.html

# The Z3 model-space pages (needs smt/.venv with z3-solver installed).
# worlds.html: seed 33 six players — the 1,238-world collapse to a solved
# view. worlds-gap.html: seed 42 four players — the completeness gap (the
# space ends certain of five cards, the notebook of four).
# worlds-768896.html: seed 768896 six players — the demo game, embedded as
# the frontend's Mycroft pane (the 44.46-trillion-world collapse).
worlds:
	spago run --quiet -p kibitzer-example -- trace 33 --players 6 > smt/trace-33.json
	smt/.venv/bin/python smt/worlds_trace.py smt/trace-33.json > frontend/public/worlds.html
	spago run --quiet -p kibitzer-example -- trace 42 > smt/trace-42.json
	smt/.venv/bin/python smt/worlds_trace.py smt/trace-42.json > frontend/public/worlds-gap.html
	spago run --quiet -p kibitzer-example -- trace 768896 --players 6 > smt/trace-768896.json
	smt/.venv/bin/python smt/worlds_trace.py smt/trace-768896.json --embed > frontend/public/worlds-768896.html

# The bettor page (EV over proof). BETTOR_SEED picks the featured game —
# 11 is the corpus's best genuine call (wakes at 82% into an 82% hazard,
# bets immediately, correct, nine events before proof); 33 is the honest
# bore (no earlier call existed). smt/bettor-validation.jsonl (from
# bettor-validate) feeds the calibration table when present.
BETTOR_SEED ?= 11
bettor:
	spago run --quiet -p kibitzer-example -- trace $(BETTOR_SEED) --players 6 > smt/trace-$(BETTOR_SEED).json
	smt/.venv/bin/python smt/bettor.py smt/trace-$(BETTOR_SEED).json \
		$(if $(wildcard smt/bettor-validation.jsonl),--validation smt/bettor-validation.jsonl) \
		> frontend/public/bettor.html

bettor-validate:
	spago run --quiet -p kibitzer-example -- traces 200 --players 6 > smt/traces-6p.jsonl
	smt/.venv/bin/python smt/bettor.py --validate smt/traces-6p.jsonl --jobs 6 > smt/bettor-validation.jsonl

bundle:
	spago bundle -p kibitzer-frontend

serve:
	npx http-server frontend/public -p $(PORT) -c-1 --cors

clean:
	rm -rf output .spago frontend/public/bundle.js
