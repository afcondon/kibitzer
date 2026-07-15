# Componentization, the widget library, and the worlds canvas

*Planned 2026-07-14. The "simple example" has outgrown one Halogen
component; this captures the restructuring before the next growth
spurt (Methods tab, worlds canvas, perspective switcher).*

## 1. Halogen child components — DONE 2026-07-14 (overnight)

Landed as `Kibitzer.Frontend.Component.{TransportBar, ControlPanel,
CascadeHost}`; App is now genuinely just the store
(config/game/position/playing/tab/packView), `Types` is pure data
(Game + Tab + accessors), and `View.Timeline` is gone. Decisions made
in the doing:

- **`packView` is a controlled input** on CascadeHost (with a
  `ViewChanged` output), not local state — tab switches destroy and
  remount the component, and the Packs|Grid choice must survive them.
  The grid sub-toggles (wiring, DAG) stay local and reset on remount.
- **ControlPanel owns the seed *draft*** (typed-but-uncommitted text);
  outputs are whole configurations (`DealRequested`/`RandomRequested`),
  so the parent never sees form fragments.
- **TransportBar collapses to two intents** (`Scrubbed Int`,
  `PlayToggled`) — step/jump are just scrubs to computed positions,
  clamped by the parent.
- **Game identity for `receive`**: `Game` gained a `movement` field so
  `gameKey = (seed, players, movement)` detects a genuine re-deal (the
  simulation is pure, so equal keys mean identical games).
- Browser smokes now live in `smoke/` (grid 18 / packs 12 / dag 11 /
  controls 14 — the last purpose-built for the new components).

Original decomposition target (as built):

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

## 2½. The radial DAG (Andrew, 2026-07-14) — DONE 2026-07-15

The layered skyline as a series of orbits: depth becomes radius.
Orientation choice made by the domain: **observations on the outermost
ring, derivations collapsing inward, the envelope certainties at the
bullseye** — the argument literally closes in on the truth, and it
rhymes with the packs view's envelope-at-centre geometry.

Landed as `Kibitzer.Frontend.Cascade.Radial` + a three-way layout
(Table | Skyline | Orbits buttons on the grid toolbar). As planned:
filtered radial force per ring, link forces along premise edges,
collide, hylograph-simulation end to end; the morph generalized to
`{from, to, t}` over three position maps (notebook cell, skyline slot,
live orbit position), so any pair morphs and mid-flight reversals stay
continuous. Lessons from the doing:

- **Angle is feed order** (twelve o'clock, clockwise) — the skyline's
  x-axis curling into a circle; mid-game the un-swept arc *is* the
  future, which reads beautifully.
- **Anchor springs are load-bearing**: radial forces don't constrain
  angle, so the linked web contracts tangentially into a clot without
  a whisper (0.05) of pull toward each fact's chronological slot.
- **Envelope facts take no physics links** — their premises drag them
  off the bullseye otherwise. The drawn provenance edges are computed
  from mark positions, not sim links, so nothing visual is lost.
- Found and fixed a pre-existing race: an animation frame scheduled
  before a view teardown could redraw into cleared DOM
  (`viewReady` gate in CascadeHost).
- dag-smoke grew into a 20-check three-layout suite (morphs, ring
  guides, orbit physics, bullseye distances on a solved game).

## 2¾. The cross-referenced cascade (Andrew, 2026-07-15) — DONE same day

Built as designed below, same session. Notes from the doing: the two
hosts are two instances of CascadeHost (packs / grid) with per-mode
container ids (`#packs-view` / `#cascade-view`); the packs lost their
rail/strip (the orbits column carries verdict + sparkline); hover is
`Maybe Crossref.Hover` in App, flowing down as input and back up as
`HoverChanged`; `Kibitzer.Frontend.Crossref` closes hover seeds over
premise ancestry, so hovering a deep fact lights the whole argument
that fed it — tokens, edges, bubbles, terminal lines. Grid default is
now Orbits. Andrew expects this page to become the principal view,
behind a clean intro page (queued below as the tab restructure).

### Original design (as built)

Three columns on one tab: **packs on the left, the event terminal in
the centre, orbits on the right** — the two circular views flanking
the stream they're both derived from, with hover cross-highlighting
stitching them together:

- hover a possibility bubble (packs) → highlight the orbit tokens of
  the facts that constrain that (location, card) pair, and the
  terminal lines of their source events;
- hover an orbit token → highlight its terminal line (same E-number)
  and the pack bubbles it killed or confirmed;
- hover a terminal line → light up everything that event taught.

Joins are already in the data: orbit token ↔ event by
`justification.source`; fact ↔ bubble by claim (player/card or
envelope/card); event ↔ facts via the cascade frames. Mechanics:
CascadeHost already isolates one sim + RAF loop — this wants either
two hosts side by side (packs host + orbits host) with the parent
carrying a shared `highlight :: Maybe HoverKey` passed down as input,
or one host owning both sims. Two sims alive at once is new but each
is small (147 and ≤147 nodes). Hover events ride the existing
HS-listener bridge — HATS `withBehaviors` already provides
`onMouseEnter`/`onMouseLeave` (verified 2026-07-15), so no upstream
ask is needed.

E-number tokens (2026-07-15) were step one of this: the orbit view
now speaks the terminal's vocabulary.

## 3. The worlds canvas (Methods tab centrepiece) — DONE 2026-07-15

Built as two static pages (make worlds): worlds.html (seed 33/6p, the
1,238-world collapse to a solved view) and worlds-gap.html (seed 42/4p,
the completeness gap: certainty dots fill when the space agrees on a
column, gain an ink ring when the notebook knows it too — the game ends
five dots, four rings, Ballroom naked). Design notes vs the plan below:
worlds_trace.py replaced the imagined worlds_trace recipe — Z3 only
enumerates once (binary-searched first position under the cap); replay
is pure evaluation, and the optimal solve moment falls out of the
replay (all survivors agree on the envelope) with no per-position
solver probes. Finding: on ten 6p seeds probed the engine's envelope
timing equals the optimum — the gap lives in the hand cards, hence the
per-column rings. The pedagogical-seed hunt (optimal strictly earlier
than engine on the envelope) found nothing at 6p; if one is ever
wanted, probe more seeds with the same script.

### Original design (as sketched)

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
