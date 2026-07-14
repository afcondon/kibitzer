# Componentization, the widget library, and the worlds canvas

*Planned 2026-07-14. The "simple example" has outgrown one Halogen
component; this captures the restructuring before the next growth
spurt (Methods tab, worlds canvas, perspective switcher).*

## 1. Halogen child components

Today `Kibitzer.Frontend.App` is one `mkComponent` with pure render
helpers. That was right at three panes; it is wrong at seven-and-
growing. Target decomposition — actual components with slots, so
pieces move between layouts without refactoring:

| component | input | output | notes |
|---|---|---|---|
| `TransportBar` | position, max, playing | `Scrubbed Int`, `Stepped`, `PlayToggled` | pure |
| `ControlPanel` | seed/players/board | `Dealt config`, `Randomed` | pure; the widget-library dogfood case |
| `Terminal` | log prefix | (none) | pure |
| `Notebook` / `Feed` | Knowledge snapshot | (none) | pure |
| `CascadeHost` | game, position, view mode | `ScrubRequested Int` | owns HATS/sim/RAF lifecycle |
| `WorldsCanvas` (future) | worlds trace, position | (none) | owns a canvas + its own RAF |

Principles:

- **Pure panes** stay `H.ComponentHTML` functions where they have no
  state and no lifecycle — componentize only what owns a resource or
  local state. The real wins are `CascadeHost` (HATS containers, the
  simulation handle, the RAF bridge, the morph/anim state all move out
  of App) and `TransportBar`/`ControlPanel` (reusable chrome).
- **The parent stays the store**: game + position + tab is the whole
  shared state; children receive it as `Input` and raise intents as
  `Output`. No global bus; the existing `HS.Listener` pattern stays
  internal to `CascadeHost` for its RAF/HATS callbacks.
- `receive` on `CascadeHost` diffs input (position changed → sync anim;
  game changed → rebuild sim) — moving today's `syncCascadeMove` /
  `initCascadeView` logic behind a component boundary largely verbatim.

## 2. Dogfooding hylograph-components

Surveyed 2026-07-14: `hylograph-components` is a **chart** library
(BarChart, ScatterPlot, LinePlot, PieChart, Treemap, Heatmap, Axis,
Legend, Annotation, Frame, Theme, Binning…). It has no UI-control
widgets. Kibitzer therefore levies new requirements upstream rather
than adopting today:

- **ControlPanel** — labelled fields (text, select, checkbox-toggle,
  buttons) in the house typographic style; kibitzer's seed/players/
  board/deal/random panel is the reference client.
- **Transport** — play/pause/step/jump + scrubber + position readout;
  every timeline-driven demo in the showcase family wants this.
- **ToggleGroup / view switcher** — the Packs|Grid|(DAG) pattern.
- **Legend**: exists for charts — evaluate whether its API can express
  kibitzer's glyph legends (text glyphs, accent items, embedded
  toggles); if not, that's requirement four.
- Candidate adoptions from the existing set once the Methods tab
  lands: `Axis` (worlds-remaining strip), `Heatmap` (worlds matrix in
  SVG form), `Legend`.

Sequencing: define the component boundaries here first (§1), then
propose the widget API upstream shaped like what kibitzer actually
needed — requirements from a real client, not speculation.

## 3. The worlds canvas (Methods tab centrepiece)

From the collapsing-worlds illustration (`smt/worlds_mock.py`): animate
the full collapse — up to ~1500 rows × 21 columns of tiny dots —
**Canvas, not SVG** (30k+ marks; a `<canvas>` in a HATS-free component,
drawn per frame from typed arrays). Design:

- One canvas: rows = consistent worlds, columns = cards, colour =
  location; worlds wink out as events land (fade rows, compact
  upward); columns going monochrome get the certainty dot above.
- Data precomputed offline (`worlds_trace.py`, to write): for the
  chosen seed, per position, the surviving world set (ids into the
  position-0 enumeration) — the browser only replays membership.
- **Seed criterion** (pedagogical maximum): watcher solves before the
  winning accusation AND the Z3-optimal watcher solves strictly
  earlier than the engine. Hunt recipe: add `solvedAt` to the corpus
  emitter; binary-search the optimal's solve position per solved seed
  (log₂(80) × ~44 UNSAT queries per probe); pick the seed with the
  widest optimal-vs-engine margin at six players classic.
- Placement: Methods tab, SMT rung, beside the side-by-side twins.
