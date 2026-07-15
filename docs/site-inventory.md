# Site inventory — everything the observatory serves

*2026-07-15, end of day. The record of every page and tab as built,
before tomorrow's session refactors the pieces into a final version.
Everything below rides the single static server on :3026 (Bosun
lazy-spawns it; `make serve` is the manual fallback) — any file in
`frontend/public/` is automatically reachable, no route registration.*

## The app — `/` (index.html + bundle.js)

`make bundle`. One Halogen app, four tabs (`Types.Tab`), the seed in
the top nav (seed input + recycle reroll), URL-addressable config
(`?seed=42&players=6&moves=1`).

| tab | contents | refactor notes |
|---|---|---|
| **Play** (PlayTab) | four columns: ground-truth table, event terminal, watcher's ✓/× notebook, "How the Watcher Knows" derivation feed | |
| **Cascade** | the cross-referenced three-column view: possibility packs \| terminal \| orbit DAG (Table/Skyline/Orbits morphing layouts), hover lights the full story across all three | Andrew expects this to become **the principal page**, behind a clean intro page |
| **About** | prose | queued for a refresh around the ⊢/⊨/P story |
| **Code** | exhibits | Sigil/Specimen spike still pending (plan §6) |

## The static pages (all regenerable from the Makefile)

| page | make target | what it shows |
|---|---|---|
| `/skylines.html` | `make skylines` | curated small multiples of complete derivation DAGs across seeds (shallow sweeps, depth-15 cathedrals, maximum breaks, uncracked games) |
| `/orbits.html` | `make orbits` | the same curation bent into circles — depth as radius, envelope at the bullseye |
| `/worlds.html` | `make worlds` | the ⊨ view, seed 33/6p: Z3 enumerates every consistent world at the first countable moment; scrub the collapse from 44,460,928,512,000 legal deals ("Too big to show", pinned mono columns) down to solved; collapse curve on log paper as scrubber |
| `/worlds-gap.html` | `make worlds` | the completeness gap, seed 42/4p: certainty dots when the space agrees, ink rings when the notebook catches up — ends five dots, four rings (Ballroom naked) |
| `/bettor.html` | `make bettor` | the P view: uniform posterior + race hazard + the two-clause call rule; featured seed 11; 200-game calibration table and the finding (the posterior snaps, the edge is the forced coin flips) |

Generators: `example/src/{Skylines,Orbits}.purs` (PS, via the example
CLI) and `smt/{worlds_trace,bettor}.py` (Python + Z3, from `trace`
JSON emitted by the example CLI). Validation corpus:
`make bettor-validate` → `smt/bettor-validation.jsonl` (committed;
~35 min at `--jobs 6`).

## The conceptual map the refactor should express

Three views of one event log, one column each:

- **⊢ the engine** — orbits/skylines/cascade: derivations, growing
- **⊨ the solver** — worlds pages: model sets, shrinking
- **P the bettor** — bettor page: measure, concentrating (or snapping)

The intro page's job is to set up the game and this trinity cleanly;
the Cascade tab is the working instrument; the static pages are the
gallery/methods wing. Launch path (plan §6): `make dist` →
`cloudflare-sites/kibitzer/` → kibitzer.hylograph.net; GitHub remote
still pending (repo is local-only).

## Everything else that serves the pages

- `smoke/` — four puppeteer suites (grid/packs/dag/controls) against
  :3026; static pages have no smoke (generated, reviewed by
  screenshot).
- `smt/` — `optimal_watcher.py` (the property-test oracle),
  `worlds_trace.py`, `bettor.py`, `corpus.jsonl`, `traces-6p.jsonl`,
  `bettor-validation.jsonl`. Traces (`smt/trace-*.json`) are
  gitignored — regenerable.
- Docs that carry the design record: `componentization-plan.md`
  (§1–§3 done), `smt-jtms-brainstorm.md` (the ⊢/⊨ correspondence +
  client hunts + Sugiyama prior art), `bayesian-layer.md` (the third
  column, with the measured finding), `formal-methods-follow-on.md`
  (scope: QuickCheck + SMT only), `requantise-idea.md` lives in the
  harmonia repo.
