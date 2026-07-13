# Plan: the inference cascade as a Hylograph showcase — kibitzer.hylograph.net

*Status: planned, not started. 2026-07-13.*

## Context

The derivation feed is honest but flat: a list. The structure it hides
is exactly what makes the watcher interesting — *relationships*. Which
facts licensed which; the moment a third card pins a hand and sixteen
exclusions avalanche out of it; a disjunction born at E2 quietly losing
candidates for sixty events and then snapping shut. The plan: a
Hylograph-rendered view where facts **cascade in** under the General
Update Pattern (Hylograph HATS has first-class GUP — `GUPSpec` with
enter/update/exit `PhaseSpec`s in `Hylograph.HATS`, animated by
hylograph-transitions), published as **kibitzer.hylograph.net** — a
Hylograph showcase in its own right.

## Prerequisite: the full premise DAG (core change)

Today `Justification` carries `rule`, `source` (triggering event) and
`origin` (show-event a disjunction resolved from) — enough for prose,
not enough to *draw* the cascade. Extend it:

```purescript
type Justification =
  { rule :: Rule
  , source :: EventId
  , origin :: Maybe EventId
  , premises :: Array FactId   -- NEW: the facts this derivation consumed
  }
```

Per-rule premise capture (each rule already looks the premises up; it
just doesn't say so):

- `OwnHand` / `SawCard` / `PassImpliesLacks` — no premises (direct observation).
- `UniqueOwner` — the `Holds` fact.
- `HandComplete` — the player's `Holds` facts.
- `EnvelopeByElimination` — one `Lacks` fact per player.
- `CategoryCount` — the `envelopeOut`/`envelopeIn` facts counted.
- `EnvelopeExcludesHands` — the `InEnvelope` fact.
- `LastCandidateHand` — the `NotInEnvelope` fact + the excluding `Lacks` facts.
- `SingletonDisjunction` — the facts that pruned the dead candidates
  (pruning must record *which* fact killed each candidate — either keep
  a `Map Claim FactId` index on `Knowledge`, or search the facts array;
  both are cheap at this size).

Consequences, all pleasant: FactIds are allocated in derivation order,
so `premises` pointing only at smaller ids gives acyclicity for free —
pin it as a property test (`all (_ < f.id) f.justification.premises`).
Golden fact *counts* are unchanged; the feed tooltips get better prose
for free ("because F12, F31").

Then a pure, tested cascade model in core (`Kibitzer.Cascade`):

```purescript
type CascadeFrame =
  { newFacts :: Array Fact        -- born at this position
  , depth :: Map FactId Int       -- longest premise chain within the frame
  , edges :: Array { from :: FactId, to :: FactId }
  , disjunctionStates :: ...      -- born / pruned / resolved this frame
  }
cascadeTimeline :: PlayerCount -> Log -> Array CascadeFrame
```

Depth drives the animation stagger; the avalanche *is* the depth
structure made visible.

## The design (primary): the notebook comes alive

Keep the 21×(N+1) grid as the spatial anchor — it is already the
reader's mental model — and let Hylograph draw on top of it:

1. **Event tick**: the triggering observation appears as a token on a
   rail beside the grid.
2. **Direct facts** fly from the token to their cells (GUP *enter*,
   stagger 0).
3. **Derived facts cascade**: arcs from premise cells to the new cell,
   staggered by derivation depth (~120ms per level), each arc pulsing
   then fading to a faint persistent trace (a "show all wiring" toggle
   keeps them). A completed hand visibly detonates: one cell fills,
   sixteen ✗ ripple down the column, envelope cells flip across the
   rule.
4. **Disjunctions** get real geometry at last: a bracket/halo linking
   the three candidate cells in the shower's column; pruning snips a
   segment (GUP *exit* on the segment, with its killing fact flashing);
   resolution collapses the bracket into the surviving cell — the E2 →
   E61 payoff becomes a visible spring under tension for 59 events.
5. **Scrubbing backward** retracts facts through the *exit* phase —
   monotonicity means the join (keyed by `FactId`) is always clean.
6. Under the timeline, a **facts-per-event strip** (tiny bars) shows
   where the avalanches live and invites scrubbing straight to them.

**Alternative kept in reserve**: a provenance-DAG timeline (x = event
index, y = derivation depth, nodes = facts, edges = premises) — better
for the *shape* of avalanches, worse as a first read; could become a
sub-toggle of the tab later. Force-directed layout rejected as primary:
organic but illegible for this data.

## Architecture

- New tab **Cascade** in the existing frontend (Game tab untouched for
  now; consider replacing the feed once the cascade proves itself).
- Root `spago.yaml` gains `extraPackages` paths to
  `../purescript-hylograph-libs/purescript-hylograph-{selection,transitions}`
  (calypso precedent); frontend package adds the deps. Views stay
  Halogen; the cascade pane is a container div that a HATS iteration
  with `GUPSpec` renders into, re-joined on position change (calypso's
  Hylograph-pane pattern). SVG, not canvas — ~150 marks max.
- All cascade *computation* stays in kibitzer-core, pure and tested;
  the Hylograph layer only joins and animates `CascadeFrame`s.

## Also in the UI overhaul: Sigil/Specimen typesetting for the Code tab

The Code tab's six exhibits are currently `<pre>` blocks with raw
string literals. As part of the same overhaul, typeset them with
**Sigil/Specimen** (`purescript-sigil` / `purescript-sigil-hats` from
hylograph-libs; the rendering engine behind `code-typography/specimen`)
— printed-quality PureScript: alignment passes, proper token colouring,
marginalia-style commentary beside the code instead of below it. Two
levels of ambition, decide at build time:

- **Modest**: run the six excerpts through Sigil tokenising/typesetting
  at build or load time, keep the exhibit structure.
- **Full Specimen**: the excerpts' commentary becomes true marginalia
  (the Specimen sidenote form) and the page reads as a two-column
  specimen sheet — which would also make kibitzer a showcase for *two*
  members of the Hylograph family at once.

Wrinkle to check at spike time: Specimen typesets whole modules; the
exhibits are fragments, so either Sigil's tokeniser is used directly on
fragments, or exhibits are re-cut as small complete modules. Fits as a
milestone alongside the cascade choreography (independent of it — can
land before or after).

## Publishing: kibitzer.hylograph.net

Everything is client-side and a game is a URL, so deployment is a
static bundle:

1. Build target in the Makefile (`make dist`): bundle + `public/` →
   `../cloudflare-sites/kibitzer/`.
2. Cloudflare Pages project + `kibitzer.hylograph.net` DNS (pattern:
   the existing hylograph.net sites in `cloudflare-sites/`).
3. Marginalia: add a `cloudflare`-host server row for the public URL
   (no startCommand — publish advisory), keep :3026 as the dev row.
4. Cross-link: About tab gets the "part of Hylograph" line; the
   Hylograph showcase index gains kibitzer.

## Milestones

1. **Premise DAG** (core): `premises` on Justification, per-rule
   capture, acyclicity property, goldens re-pinned (counts unchanged).
2. **Cascade model** (core): `Kibitzer.Cascade` + tests (depths,
   edges, disjunction lifecycle).
3. **Hylograph spike**: extraPackages wiring; Cascade tab joins facts
   onto the grid, enter-only, no arcs. Proves the HATS/Halogen seam.
4. **Choreography**: arcs, depth stagger, disjunction brackets,
   backward-scrub exits, facts-per-event strip.
5. **Publish**: `make dist`, Pages project, DNS, Marginalia rows,
   README/About links.

## If this goes to HackerNews (launch-readiness checklist)

The pitch writes itself — *"a Cluedo spectator who never sees a card
can often name the murderer; here's the metadata doing it, live"* —
but a Show HN gets one shot, so before posting:

- **Public GitHub remote** (`afcondon/kibitzer`) — it's a
  show-your-work crowd; the repo, README and tests are half the appeal.
- **Curated seeds**: a small "greatest hits" — a seed where the watcher
  fully solves it, the E2→E61 slow-burn disjunction, the seed-42-moves
  test-the-theory game — surfaced as one-click links ("watch the
  watcher solve it"), not left to the Random button. Optional: a
  seed-hunt script that finds watcher-wins for the shortlist.
- **Landing experience**: default view should *animate on arrival*
  (autoplay a curated seed?); About is the second click, not the first.
- **Link previews**: OG/meta tags with a good still of the split
  screen; page weight check (bundle is ~330 KB, fine); a quick pass on
  narrow screens (the media query exists; verify the grid).
- **Discussion-bait in the About tab**: the stats table and the
  "board protects the players" finding are what comments will argue
  about — make the methodology one click away (stats mode command,
  seeds 1–100, policy caveat: random suggesters, sound-not-complete
  watcher). Pre-empt the two obvious critiques by owning them.
- **Show HN etiquette**: author posts it, first comment explains what
  it is and what's deliberately simplified; the SMT/TLA+/Lean plan is
  the natural "what's next" reply when someone asks about completeness.

## Open questions (for when we pick this up)

- Grid-anchored cascade as the only view, or with the DAG-timeline as
  a toggle?
- Does the Cascade tab eventually *replace* the Game tab's feed, or
  stay a sibling?
- Movement games: does the board map join the choreography (tokens as
  event sources for Moved ticks), or stay static on this tab?
