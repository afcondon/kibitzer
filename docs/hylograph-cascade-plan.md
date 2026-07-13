# Kibitzer phase 3 — the Hylograph cascade viewer (detailed implementation plan)

## Context

The derivation feed is honest but flat. The structure worth *seeing* is relational: which facts licensed which, the avalanche when a hand completes, a disjunction born at E2 losing candidates for sixty events and snapping shut. Goal: a **Cascade tab** where facts animate onto the notebook under the General Update Pattern, rendered by Hylograph HATS — making kibitzer a Hylograph showcase (target: kibitzer.hylograph.net). This supersedes the sketch in `docs/hylograph-cascade-plan.md` with an API-grounded plan; after approval, copy the substance back into that doc and commit.

**Ground truth from exploring the Hylograph libs** (all verified, not assumed):

- The join: `forEachWithGUP :: String -> ElementType -> Array a -> (a -> String) -> (a -> Tree) -> GUPSpec a -> Tree` in `Hylograph.HATS` (purescript-hylograph-selection). `GUPSpec a` = enter/update/exit `PhaseSpec`s; `PhaseSpec = { attrs :: Array Attr, transition :: Maybe TransitionConfig }`.
- The `TransitionConfig` GUP uses is `Hylograph.Internal.Transition.Types` — `{ duration, delay, staggerDelay :: Maybe Number, easing }`, helpers `transition` / `staggeredTransition`. **Beware**: `Hylograph.Transition.Engine` (hylograph-transitions) exports a *different* `TransitionConfig` — do not import that one for phases.
- Entry point: `rerender :: String -> Tree -> Effect RerenderResult` (`Hylograph.HATS.InterpreterTick`) — selector-string container, returns `{ selections, transitions :: Maybe HATSTransitions }`.
- **Nothing in the repo ever calls `tickTransitions`** — `rerender` creates transitions but no showcase animates them. The RAF driver is ours to write (`Hylograph.HATS.Transitions.tickTransitions :: Number -> HATSTransitions -> Effect TransitionResult`, + `Hylograph.Transition.RAF.requestAnimationFrame/performanceNow`). Exit elements are only removed by the tick loop — the driver is mandatory for correct GUP, not a nicety.
- **Only numeric attributes animate** (interpreter parses attr values to Number). Design consequence: choreography = positions (cx/cy/x/y/x1..y2), radii, opacity. Straight hairline `Line`s for provenance (x1,y1,x2,y2 all numeric), no path morphing. Fits the Swiss style.
- **Stagger is per-index only** (`delay = base + staggerDelay × idx`). Design consequence: sort the entering-facts array by derivation depth, so index-stagger *is* depth-stagger.
- Halogen hosting pattern (from showcase `halogen-spider/src/SiteExplorer/App.purs`): render an empty `HH.div [ HP.id "cascade-view" ] []`, call `rerender "#cascade-view" tree` from `handleAction` in `Effect`; HATS owns all DOM under the container; events bridge back via `Halogen.Subscription` (we already use `HS.create` for the ticker).
- Package wiring: three `extraPackages` path entries in the root spago.yaml — `hylograph-selection` (also needs) `hylograph-graph`, `hylograph-transitions`, at `../purescript-hylograph-libs/purescript-hylograph-*`. They inherit kibitzer's registry 73.3.0 (their own pins are ignored as path members); no expected conflicts, verify at the spike.

## Milestone 1 — core: full provenance (premises + origins)

Extend `Justification` in `core/src/Kibitzer/Knowledge.purs`:

```purescript
type Justification =
  { rule :: Rule
  , source :: EventId
  , origins :: Array EventId     -- was `origin :: Maybe EventId`; show-events involved
  , premises :: Array FactId     -- NEW: facts this derivation consumed
  }
```

Per-rule capture in `Infer` (each rule already looks these up; make it say so). Add `factIdFor :: Claim -> Knowledge -> Maybe FactId` (linear scan of `facts` is fine at this size):

- Direct rules (`OwnHand`/`SawCard`/`PassImpliesLacks`): premises `[]`.
- `UniqueOwner`: the `Holds` fact. `HandComplete`: the player's `Holds` facts. `EnvelopeByElimination`: one `Lacks` per player. `CategoryCount`: the counted envelope facts. `EnvelopeExcludesHands`: the `InEnvelope` fact. `LastCandidateHand`: the `NotInEnvelope` fact + excluding `Lacks` facts.
- `SingletonDisjunction`: the facts that pruned dead candidates (lookup via `factIdFor` on `Lacks shower c` / `Holds other c`); origins = [disjunction source].
- `DisjunctionCapacity` / `DisjunctionPigeonhole`: premises = the player's `Holds` facts (capacity) / pruning facts where crisply attributable; origins = source events of the involved disjunctions. Partial provenance here is acceptable and documented — arcs need an anchor, not a proof term.

Ripples: `Describe.describeFact` (origins plural), Feed view, KnowledgeSpec assertions (`origin` → `origins`). New property in PropSpec or KnowledgeSpec: **premise acyclicity for free** — `all (_ < f.id) f.justification.premises` for every fact, every perspective, both modes. Golden fact *counts* unchanged (re-pin only if Eq-shaped assertions bite).

## Milestone 2 — core: `Kibitzer.Cascade` (pure, tested)

```purescript
type CascadeEdge = { from :: FactId, to :: FactId }
type CascadeFrame =
  { newFacts :: Array Fact          -- born at this position, sorted by (depth, id)  ← index-stagger = depth-stagger
  , depth :: Map FactId Int         -- longest premise chain within the frame (0 = direct)
  , edges :: Array CascadeEdge      -- premise → conclusion, including into older facts
  , disjunctions :: Array Disjunction  -- live state at this position (for brackets)
  }
cascadeTimeline :: PlayerCount -> Perspective -> Log -> Array CascadeFrame   -- |log|+1, index-aligned with knowledgeTimeline
```

Tests (`Test.CascadeSpec`): depths are 0 for observation-rule facts; every edge's `from` precedes `to`; frame newFacts partition the final fact list; seed-42 golden spot-checks (the E61 resolution frame has depth ≥ 1 and an edge from a pass-fact).

## Milestone 3 — frontend: wiring spike (static SVG notebook via HATS)

- Root `spago.yaml`: add the three `extraPackages`; frontend deps += `hylograph-selection`, `hylograph-transitions`, `refs`. **Gate: `spago build` green against registry 73.3.0** before anything else.
- New tab `CascadeTab` (Types/App/header, same pattern as About/Code). Its pane: `HH.div [ HP.id "cascade-view" ] []` — Halogen never renders children under it.
- New module `Kibitzer.Frontend.Cascade.Scene` (pure `Tree` building): the whole notebook as SVG — layout constants module computes cell centres `(cardIndex, column) -> {x, y}` with category gaps; row labels as `Text`, grid hairlines as `Line`, header letters. Static render on `SetTab CascadeTab` via `rerender "#cascade-view"`.
- Verify: tab shows the SVG grid, switching tabs back and forth doesn't duplicate or orphan DOM (HATS diffs by key).

## Milestone 4 — GUP marks + the RAF driver

- `Kibitzer.Frontend.Cascade.Driver` (~40 lines, the piece nobody has written): holds `Ref (Maybe { frameId :: AnimationFrameId, transitions :: HATSTransitions, lastTs :: Timestamp })`; `start :: Driver -> HATSTransitions -> Effect Unit` cancels any running loop, then RAF-loops `tickTransitions (now - lastTs)` until `Complete`. **Upstream candidate**: after it works, offer it to hylograph-transitions as the missing GUP clock.
- Fact marks: `forEachWithGUP "facts" Group factsUpTo keyByFactId markTemplate gupSpec` — datum = fact + cell coords + depth + fresh-this-frame flag. Mark = small `Circle`/`Text` glyph at its cell (✓ filled circle, ✗ cross as Text, envelope column accent). Enter phase: `attrs` start at the event-rail anchor with opacity 0 and animate to cell position, `staggeredTransition (Milliseconds 500.0) 90.0` (index = depth order from Milestone 2's sorting). Update: identity/no-op quick transition. Exit (backward scrub): opacity+r → 0, removed by the driver on completion.
- App integration: every position-changing action (`Scrub`, `Tick`, `StepBack/Forward`, `Jump*`, new game), when `tab == CascadeTab`, rebuilds the tree for the new position and calls `rerender` + `Driver.start`. Rapid scrubbing is safe: each rerender supersedes; driver cancels the old loop. If thrash shows, debounce by one animation frame.
- State: `driver :: Maybe Driver` created at `Initialize` (Ref in State).

## Milestone 5 — choreography

- **Provenance hairlines**: joined `Line`s keyed by edge (`from-to`), from premise cell to conclusion cell; enter opacity 0 → 0.7; update phase settles them to 0.12 (the faint persistent wiring); a header toggle "wiring" flips persistent opacity 0.12 ↔ 0. Fresh-frame edges slightly thicker via class.
- **Disjunction brackets**: join keyed by disjunction source event; vertical `Line` spanning the candidate cells in the shower's column + candidate tick marks; prune = update transition shrinks the y-extent; resolve/exit = fade. This is the E2→E61 spring made visible.
- **Event rail**: single-datum join; current event token (Text) at the rail position; the enter-from anchor for direct facts.
- **Facts-per-event strip**: Rect-join sparkline under the timeline (per-event newFacts counts from cascadeTimeline — invites scrubbing to avalanches). Clicking a bar = `Scrub` (behavior via `withBehaviors [onClick (HS.notify listener (Scrub i))]` — the HS bridge).
- CSS: only container sizing/typography; all marks are SVG attrs.

## Milestone 6 — polish, Sigil spike, publish

- **Sigil/Specimen Code tab** (from the earlier addendum, gated spike): try `purescript-sigil` tokeniser on the six fragments; if fragments don't tokenise standalone, re-cut exhibits as tiny complete modules; modest ambition first (tokenised colouring), full Specimen marginalia only if the spike is smooth.
- README + About: cascade section; curated-seed links (launch checklist item — a "watch the avalanche" link straight to a big frame).
- Publish: `make dist` → `../cloudflare-sites/kibitzer/`; Cloudflare Pages project + `kibitzer.hylograph.net` DNS; Marginalia: cloudflare-host server row for the public URL (no startCommand), keep :3026 dev row; cross-link from the Hylograph showcase index.

## Verification

- Core: `spago test -p kibitzer-core` (CascadeSpec + acyclicity property + existing suite; goldens re-pinned only if Eq ripples).
- Frontend, puppeteer against :3026 per milestone: (3) SVG grid present, 21 rows; (4) scrub to end → circle count == factCount, scrub to 0 → 0 marks and **no orphaned exit elements** (the driver test), console clean; (5) wiring toggle flips line opacity, bracket count == live disjunctions at a pinned seed/position; screenshot review at seed 42 positions {0, 62, end}.
- Perf: hold arrow-key scrub for 5s — no RAF leak (frameId cancel), no unbounded DOM growth.

## Risks / decisions taken

- Full-SVG notebook on the Cascade tab (not an overlay on the HTML table): HATS must own its DOM; two renderers over one grid would fight. The Game tab keeps the HTML notebook; the Cascade tab is the animated twin. Decide *after it exists* whether it replaces the Game tab's right pane.
- Registry 73.3.0 compat of the three local libs is unverified until the Milestone-3 gate (their bounds are ordinary stdlib ranges; low risk).
- Depth-stagger via sorted enumeration is an approximation (within-depth items stagger slightly too) — acceptable, reads as a cascade.
- `hylograph-graph` is a transitive dep we don't use directly; it rides along as a path member.
