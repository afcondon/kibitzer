# Kibitzer — pedagogical restructure plan (Phase A)

*2026-07-26. Reorient the app as a progressive-enhancement teaching spine;
the demo video falls out of it. File-level scope, grounded in a frontend
map. Effort tags: **S** ≲ half-day, **M** ~1–2 days, **L** > 2 days.*

## The path we're building toward

1. **Watch a game unfold** (user paces it) → a stream of facts.
2. **The watcher's notebook** — shown in the Cascade-styled SVG grid
   (`TableView`), first **unwired** (raw stream), then **wired** with the
   discovery stepper pausing on individual deductions (premise hairlines
   + `[E… · rule]` tooltip). Replaces today's plain HTML notebook.
3. **The graphical Cascade** — same component, morphed to force-packs and
   orbits; run fast once, then closeups.
4. **A SMT / worlds page** — stepped through by world-reduction.

## Key architectural findings (from the frontend map)

- **One component, many faces.** `Component/CascadeHost.purs` hosts the
  SVG grid; `Cascade/Layout.purs GridLayout = TableView | SkylineView |
  RadialView` are morph targets; `Packs/*` is a sibling force instance.
  The pedagogical progression is mostly **toggles + morphs of CascadeHost**
  (`wiring :: Boolean`, `gridLayout`, `packView`), not new views.
- **"Wiring" = provenance hairlines + hover-ancestry, driven by hovered
  fact id** — `Cascade/View.purs` `edges` (gated by `wiring`), disjunction
  `brackets`, and `Crossref.implicated` lighting the premise ancestry
  (`lit`/`dimmed`). No literal crosshair widget exists.
- **The tooltip sentence is core, already perfect.**
  `core/Kibitzer/Describe.purs` `describeFact`/`ruleName`/`eventRef`
  produce exactly `"[E102 · held by no one] Mrs. Peacock is in the
  envelope"` and the `(resolving the card shown at E61)` suffix.
- **Every fact carries `justification.rule`** (`core/Kibitzer/Knowledge.purs`),
  already read in the frontend — so a direct-vs-deductive classifier is
  free.
- **Stepping is purely per-event today** (`App.State.position`, an index
  into `game.result.log`; 700 ms `Tick`). No fact/rule/discovery index
  exists yet.

## The work

### 1. Discovery stepper — the one real new feature. **M**
The keystone. Both a pedagogy device and the pacing answer (retires the
700 ms metronome for the comprehension beats).

- **Index (S).** Build `discoveries :: Array { position, factId, rule }`
  — the deductive facts in timeline order. Derive from the per-position
  `newFacts` already in the `Game` bundle (`Types.purs`; `Cascade/View
  stripFor` already reads `fr.newFacts`), filtered to
  `rule ∈ {SingletonDisjunction, UniqueOwner, HandComplete,
  LastCandidateHand, DisjunctionCapacity, DisjunctionPigeonhole,
  EnvelopeByElimination, CategoryCount, EnvelopeExcludesHands}` (i.e.
  everything except the direct `OwnHand`/`SawCard`/`PassImpliesLacks`).
- **Focused-fact driver (S–M).** Add `focused :: Maybe FactId` to state.
  Feed it through the SAME path hover uses (`Crossref.implicated` →
  `redraw`), so the focused fact lights its premise ancestry and edges
  programmatically. Essentially "hover, but from a step."
- **Transport action (S).** Add ⏭-to-next-deduction / ⏮ buttons that set
  `position` to the discovery's position AND set `focused`, then pause.
- **Visible callout (S).** The `[E… · rule]` tip is a native SVG
  `<title>` today (mouse-only). For stepped focus, render `describeFact
  focused` as a styled callout box (the floating box in the screenshots)
  so it shows without a mouse.

**Controls — the floating block (locked).** The linear `TransportBar` is
replaced by a floating control block pinned top-right, written from
scratch here (it's a mostly-CSS construct — no ecosystem widget for it).
Four stacked rows: ① wide play/pause · ② back / fwd (event step) · ③ prev
/ next (discovery step) · ④ start / end. Text buttons, or text + the
classic icons, to keep the two step-pairs unambiguous. The circular
orbits viz leaves the corner clear, so the block never overlaps data. So
the event stepper and discovery stepper are simply adjacent rows of one
control — no mode toggle.

### 2. Promote the wired notebook to page 1. **S–M**
Replace `View/Notebook.purs notebookPane` (App.purs PlayTab `split4`
col 3) with a `CascadeHost` grid instance in `TableView` + `wiring`.
CascadeHost is already mounted twice, so a third instance is
mechanical; the work is wiring its inputs on the page-1 layout.
**Always wired, unexplained** — drop the unwired mode entirely; the
wiring's meaning is left to emerge from the orbits view.

### 3. Event stream → top-prepending stack. **S**
`View/Terminal.purs` reverses the log and relies on CSS `column-reverse`
(in `frontend/public/style.css`) to pin newest at the bottom. For
newest-at-top: drop the `column-reverse` rule (keep the `Array.reverse`).
One CSS change + verify the `latest`/`hl` classes still track.

### 4. SMT / worlds reduction stepper. **S (likely mostly done)**
`worlds.html` already has an `informative`-position skip in its scrubber
JS (`while (… !D.informative[next-1]) next++`) — confirm its semantics
match "next world-count reduction" and expose it as a first-class
stepper button. Open question (from the script): keep seed 33 (canonical
1,238-world render) or regenerate for 768896 (needs the `smt/` Python+z3
sidecar). Whether this becomes an in-app page or stays the static page is
a separate decision.

### 5. Subtraction pass. **S–M**
- **Easy:** remove About + Code tabs (`View/About.purs`, `View/Code.purs`,
  their two `Tab` constructors, render branches, nav buttons); trim the
  `pane-note` prose blocks + masthead strap + legends.
- **Moderate:** drop the `SkylineView` morph target (`Cascade/Layout`,
  `homeOf`/`amountOf` cases, the Skyline `layoutButton`) — careful, it
  shares morph code with Table/Radial. Strip the Board toggle from
  `ControlPanel` (keep player-count).
- **Board — strip entirely (locked).** Remove `View/Board.purs boardPane`,
  the `board`/`movement` config, the `moves` URL param,
  `positions`/`positionsTimeline`, and the `Moved`/`EnRoute` event prose.
  Replace page-1 col 1 with a slim ground-truth strip (envelope + hands)
  carved from what `boardPane` drew. **Narrative note** (for the script,
  and as an in-app note): real gameplay is *less* favourable to the
  watcher — the point is not that it beats the players, but that it
  extracts *any* signal from pure metadata, and increasingly much as the
  table grows.

### 6. Deal animation — separate throwaway SVG asset. **(Phase B, not app)**
Design-over-code, video-only, never shipped. Not app work.

## Suggested order

1 (discovery index + focused driver) → 2 (promote wired notebook, exercise
the stepper on it) → 3 (stack) → 5 (subtract, now that the path is proven)
→ 4 (confirm/expose the SMT stepper). 6 runs independently in Phase B.

## Decisions (locked 2026-07-26)

- **Controls:** floating block, top-right, 4 stacked rows (play/pause ·
  back/fwd event · prev/next discovery · start/end); from scratch, CSS.
- **Discovery vs event stepper:** separate — adjacent rows of the block.
- **Board:** stripped entirely; thesis reframed to metadata-extraction
  scaling with players (not "beats the players").
- **Panes named for the libraries:** Game → **Baskerville** (the
  deduction view: wired notebook + cascade/orbits) → **Mycroft** (the
  worlds/SMT view). The spine is game → Baskerville → Mycroft.
- **One seed across all panes** at any given time. All three show the
  *same* game, so the Mycroft/worlds pane is **768896** for the demo
  (regenerate — `worlds.html` is currently seed 33).
- **Notebook:** always wired, unexplained.
- **Orbits:** strip the top legend + TABLE/SKYLINE/ORBITS switcher.

### Still open

- **Mycroft (worlds) view build:** embed the existing static `worlds.html`
  rendering (regenerated per active seed via the `smt/` Python+z3 sidecar)
  vs reimplement it in-app so it takes the seed live. Seed itself is
  settled: whatever the other panes show (768896 for the demo).

## Parking lot

- **10-player hypothesis:** tweak the rules (10 players, same
  rooms/weapons/suspects) and re-measure — expected: the watcher solves
  far more often (consistent with the monotone 3→6 climb). Cheap to test
  with the stat harness — mind the machine (single-flight, small pool).
- **halogen-widgets idea:** many "components" here are really mostly-CSS
  constructs (this floating block, the panes). To a designer the
  CSS-vs-Halogen-component line is a distinction without a difference, so
  it's worth facilitating first-class in `purescript-halogen-widgets`.
  Think about it later.

## Script implication

Stripping the board and reframing the thesis touches the video: the
Interlude's "board protects the players" beat goes away, and the Act-1 /
Interlude emphasis shifts from "the watcher beats the players" to "it
extracts signal from pure metadata, and that scales with the table." The
player-count climb (3→6, and the 10-player hypothesis) becomes the whole
statistical story. Revise the script doc when the app reframe lands.
