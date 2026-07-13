# Cascade v2 — possibility packs (the force-layout view)

*Status: planned 2026-07-13, after Andrew's design review of the grid
cascade. Open questions resolved same evening:*

- *Envelope at the **centre of the player ring**, marked by a
  non-animating rounded rect; every convergence flies radially inward.*
- *Disjunctions via the **radial force**: candidates of unresolved
  disjunctions orbit the shower's pack (one shared orbit per pack,
  dashed guide circle); pruning drops a card back into the bubble pack,
  resolution collapses the orbit. `ForceRadial` supports per-force
  filter predicates with static radius/centre — one orbit force per
  pack, rebuilt via `updateSetup` when membership changes.*
- ***Clean dots** — no monograms; the abstraction is the point: the
  watcher never sees a single card, and neither do we.*

## The design critique this answers

The grid cascade is honest but tabular — "a very nice substitute for
the simple table on the first pane" (Andrew), not the explanatory
animation it was meant to be. The flying marks aren't readable as
*reasoning*; they're readable as bookkeeping.

The replacement idea (Andrew's sketch): make **conservation** the
visible law. Each of the 21 cards is in exactly one of N+1 places
(N hands + the envelope). Render every remaining *possibility* — "card
c could be at location L" — as a bubble in L's pack. The whole game is
then watching (N+1)×21 possibilities collapse toward certainty, and
the envelope's pack collapsing to exactly three solid cards *is* the
solution appearing.

## The semantic model (pure, derived from Knowledge)

One possibility node per (location, card) pair; location ∈ players ∪
{envelope}. At six players: 7 × 21 = 147 nodes. Every node's state is
a **pure function of the Knowledge snapshot** — no incremental state
to maintain, scrubbing both directions comes free:

| state | condition (for location L, card c) | rendering |
|---|---|---|
| **Open** | nothing known | full-opacity bubble, category colour |
| **Ghost** | L ruled out (`Lacks L c` / `NotInEnvelope c`), true location unknown | ~35% opacity |
| **Confirmed** | `Holds L c` / `InEnvelope c` | full opacity + solid ink border (envelope: accent border) |
| **Gone** | c's location known to be elsewhere | absent (exits via convergence, below) |

Precedence: Confirmed > Gone > Ghost > Open. Because `UniqueOwner`
derives `Lacks` for every other seat the moment a holder is known, and
`EnvelopeExcludesHands` does the same for envelope cards, Gone and its
ghosts coincide — the state machine never glitches.

End states tell the truth: the envelope pack ends as exactly three
solid cards (one per colour) when the watcher solves it; residual
uncertainty stays visible as the same card sitting Open in several
packs at once.

## The convergence animation (Andrew's addendum — the centrepiece)

When a card's location becomes known, **every other copy flies into
the confirmed copy and is absorbed**:

- `InEnvelope c` fires (elimination: all N players shown not to have
  it) → the N ghost copies of c fly from their packs into the
  envelope's copy of c, which solidifies on impact. This *enacts* the
  deduction: it is precisely the fact that nobody has it that puts it
  in the envelope, and the animation is that argument.
- `Holds p c` fires → same movement, target is p's copy. (UniqueOwner
  made visible.)

Mechanics: exits are `Tick.Transitioning` items carrying their frozen
start position and the *key of their target node*; the per-frame scene
rebuild lerps each exiting bubble from its start toward the target's
**live** position (packs keep breathing under the sim — chasing the
live position is trivial because the scene is rebuilt every frame) and
shrinks it to the target's radius. `easeInCubic` so they gather speed
into the absorption. Optionally a one-frame radius pulse on the target
at completion.

Backward scrubbing reverses state derivation for free; resurrected
possibilities re-enter with a simple pop-in at their pack (no reverse
convergence — not worth the choreography budget).

## Layout & forces (API-grounded)

`hylograph-simulation`'s high-level API, exactly as the ForcePlayground
demo uses it:

- `runSimulation { engine: D3, setup, alphaMin }` → `{ handle, events }`.
- Forces: `positionX`/`positionY` per node toward its **pack anchor**
  (static per location), `collide (r + 1.5)` for packing, no manyBody
  (or very weak) — we want tight bubble packs, not a galaxy.
- **Pack contraction**: `handle.updateData survivors []` on every
  position change — GUP semantics keep surviving nodes' positions and
  auto-reheat, so packs visibly tighten as possibilities die. (This is
  why Gone nodes leave the sim, not just the render set.)
- Positions read with `handle.getNodes` each animation frame; the
  existing RAF→`HS.notify` bridge stays the single clock (the sim runs
  headless; we don't render from its Tick emitter — decided at spike if
  the emitter turns out more convenient).
- Anchors on grid points (Andrew's spec): players in a row/grid,
  envelope distinguished. **Open question**: envelope as (a) last grid
  cell styled in accent, or (b) centre of the player ring — the unknown
  at the heart of the table. (b) makes every convergence radial and
  reads well, but (a) is the literal sketch.
- New `extraPackages`: `hylograph-simulation`, `hylograph-simulation-core`,
  likely `hylograph-d3-kernel` (transitive). Same registry-73.3.0 gate
  as before.

## Visual encoding

- Card colour by category — three hues (suspects / weapons / rooms),
  light-theme, Swiss restraint; the envelope's three end-state cards
  are then automatically one of each colour.
- Bubble radius ~9px; 2-letter card monogram inside (fontSize ~7) so
  packs are scannable without hover — **open question**: monograms vs
  clean dots + tooltip only.
- Confirmed border: 2px ink (players) / 2px accent (envelope).
- Hover provenance everywhere (already the house pattern): native
  `<title>` per bubble = `describeFact` of the fact that set its state;
  Open bubbles get "no information yet".
- Rail, verdict line, and the facts-per-event sparkline carry over
  unchanged — they're view-independent.

## Disjunctions and the counting rules

The grid shows disjunctions as bracket spines; packs need their own
idiom. Options, to pick during review:

1. **Dashed enclosure**: a dashed accent circle around the candidate
   bubbles in the shower's pack (centroid + max-distance radius, wobbly
   under the sim but honest). A card in several disjunctions sits in
   several enclosures — busy exactly when C has shown six times, which
   the grid taught us is informative.
2. **Link forces**: candidates of one disjunction weakly attracted, so
   each "showed one of these" becomes a visible clump inside the pack.
   Prunes = clump shrinking; resolution = clump collapsing onto one
   bubble as the others' possibilities die. Most physical, most alive;
   risk: clutter with many live disjunctions.
3. **Badge ticks** on candidate bubbles (small accent notch), tooltip
   carries the detail. Quietest.

Recommendation: (2) + hover detail, falling back to (3) if six-player
games turn to soup. Counting-rule deductions (capacity/pigeonhole) get
no structural display — their `Lacks`/`NotInEnvelope` conclusions ghost
bubbles like any other fact, and the hover tooltip names the rule; the
grid view's wiring remains the place to study *why* in full.

## Where each view lives

- **Cascade tab** becomes the packs (the explanatory view, per the
  design review).
- The **grid** stays reachable — sub-view toggle on the Cascade tab
  (`Packs | Grid`) in the legend row.
- Later candidate, per Andrew's remark: the SVG grid replaces the HTML
  notebook table on the Game tab (shared component, no animation churn
  there — render at full progress). Decide after packs land.

## Milestones

- **P1 — sim spike**: extraPackages in, 73.3.0 gate; 147 static nodes
  packing around anchors; scrub does nothing yet. Proves the
  sim-clock/RAF question and pack geometry.
- **P2 — states + reconciliation**: node states from `knowledgeAt`
  snapshots; position changes diff states, `updateData` the survivors,
  ghosts fade via Tick progress; instant-render cap for big jumps
  (reuse `animationCap`).
- **P3 — convergence + disjunctions**: the fly-into-the-envelope
  choreography (and its Holds twin); chosen disjunction idiom; verdict/
  rail/sparkline wired in; hover provenance.
- **P4 — arrangement**: Packs|Grid toggle, legend, About-tab paragraph
  rewrite, smoke extension (bubble counts per pack == 21 − eliminated,
  envelope pack solid-count == envelopeIn size, convergence leaves no
  orphans).

## Verification sketch

Per position, pure invariants the smoke can assert against the DOM:
pack L's rendered bubbles == cards not Gone for L; ghost count == |lacks L|
(holder unknown); envelope solid count == |envelopeIn|; total bubbles
across packs + completed exits conserve; scrub to 0 restores 147; no
console errors; sim reheats don't leak (alpha returns below alphaMin).
