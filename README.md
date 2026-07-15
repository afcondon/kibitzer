# kibitzer

*One who watches a card game over the players' shoulders and offers
commentary — traditionally without seeing anyone's hand.*

A Cluedo (American: Clue) simulator built to demonstrate one idea: **a
watcher who is not a player, holds no cards, and never sees a card can
often work out the murderer, weapon, and room purely by inference from
metadata.** A suggestion is made; three players pass — the watcher just
learned nine facts. A fourth shows a card face-down to the suggester —
the watcher can't see it, but that's another fact, and sometimes, many
events later, it resolves into "that card must have been the Ballroom."

The split-screen web app plays a full game on the left (ground truth:
hands, envelope, every card shown) while the right side fills in the
watcher's detective notebook — every mark justified in a derivation
feed, under a running counter:

> **Cards seen: 0 — Facts inferred: 70**

That counter is the point. If a bystander can reconstruct most of a
"private" game from who-asked-whom and who-passed, the same is true of
your phone records, your DNS queries, and your encrypted-messenger
metadata. Content privacy is not metadata privacy.

It is also intended as a small, readable example of functional
programming in PureScript: algebraic data types, `Data.Set` and
`Data.Map`, folds over event streams, provenance-carrying facts, a
fixpoint of monotone deduction rules, and no partial functions.

## Quick start

```bash
make build        # spago build (all packages)
make test         # golden + property tests for the core
make example      # CLI demo: full transcript + watcher's notebook (SEED=42)
make bundle serve # web app on http://localhost:3026

make skylines     # derivation DAGs as small multiples  → /skylines.html
make orbits       # the same DAGs bent into circles     → /orbits.html
make worlds       # the Z3 model space, animated        → /worlds.html, /worlds-gap.html
make bettor       # the EV watcher-watcher's call       → /bettor.html (BETTOR_SEED=33)

spago run -p kibitzer-example -- 42 --moves --players 6   # any variant, as text
spago run -p kibitzer-example -- stats 100                # the comparison table
spago run -p kibitzer-example -- trace 33 --players 6     # one game as JSON (for smt/)
```

Web-app URLs carry the whole configuration — `?seed=42&players=6&moves=1`
reproduces a game exactly.

The dev URL `http://localhost:3026` is Bosun-routed (registered as
`kilo-papa-zulu-delta:frontend` in Bosun's fleet registry; Marginalia
project #251) — `bosun serve` lazy-spawns the static server on first
request, so `make serve` is only needed when the router isn't running.

## The observatory

The app has grown from a split screen into a small observatory — the
same event log watched several ways, all driven by one transport bar
(the seed lives in the top nav; every view is a view of one seeded
game).

**Game tab** — four columns: the ground truth table (players, hands,
envelope), the event stream as a scrolling terminal, the watcher's
✓/× notebook, and *How the watcher knows* — every fact with its rule
and provenance, fresh facts highlighted.

**Cascade tab** — the cross-referenced view, three columns stitched
together by hover:

- *Possibility packs* (left): one bubble per (location, card)
  possibility, held by a force simulation. Eliminations fade,
  located cards take a ring, and when a card is proven into the
  envelope every player's copy visibly flies into the centre.
  "Showed one of these" candidates lift onto a wide orbit and explain
  themselves on hover.
- *The terminal* (centre): the same stream as the Game tab.
- *The orbits* (right): the watcher's derivation DAG with three
  morphing layouts — the notebook **table**, the **skyline** (feed
  order × derivation depth), and the **orbits** (depth as radius,
  observations outermost, envelope certainties pulled to the
  bullseye; every mark an "E23" token naming its source event).

Hover anything — a bubble, a token, a terminal line — and its whole
story lights up across all three columns: the premise ancestry in the
DAG, the possibilities it touches in the packs, the events it came
from in the stream.

**Static pages** (all regenerable from the Makefile):

- `skylines.html` / `orbits.html` — curated small multiples of
  complete derivation DAGs across seeds: shallow sweeps, depth-15
  cathedrals, maximum breaks, games the watcher never cracks.
- `worlds.html` — the SMT view. Z3 enumerates every world consistent
  with the transcript at the first moment the space fits on a page,
  then each event visibly kills the worlds it contradicts, from
  4.4 × 10¹³ legal deals (dashed estimate, "Too big to show") down to
  the solved view — with the collapse curve on log paper as scrubber.
- `worlds-gap.html` — the completeness gap: certainty dots fill when
  the model space agrees on a card, and gain an ink ring when the
  engine's notebook catches up. One game ends five dots, four rings.
- `bettor.html` — the third column: EV over proof. The engine proves
  (⊢), the solver entails (⊨); the bettor *makes a call*. Under a
  uniform prior the worlds page read as a distribution gives the
  posterior over envelope triples; the same enumeration measures the
  hazard that some rival is already certain. It bets when confidence
  clears θ = 0.9 — or when the race forces its hand — and a 200-game
  silent run scores its calibration (a bettor who says "90%" should
  be right nine times in ten).

The `smt/` sidecar (Python + Z3) holds the optimal-watcher oracle the
property tests compare against, and the worlds-page builder. The
`smoke/` directory holds four puppeteer suites that exercise all of
the above against the dev server.

## The two load-bearing ideas

**1. A player is just a watcher with extra observations.** There is one
inference engine. Knowledge is built by folding `learn` over a stream
of observations; the watcher folds over the public stream, a player
folds over the same stream plus their private sightings (their dealt
hand; cards shown to or by them). Players even decide when to accuse by
running the same engine on their own stream — the simulator dogfoods
the watcher's logic.

**2. Everything is a projection of one event log.** The simulator
produces ground truth (`Kibitzer.Event`); a single function

```purescript
observe :: Perspective -> Event -> Observation
```

is the entire privacy model (`Kibitzer.Observe`). The watcher's
`ObsShowed` has `card: Nothing`; the shower's and receiver's have
`Just card`. Rendering the game at position *n* is folding the first
*n* observations — so the timeline scrubber is free, and every game is
a pure function of its seed (a hand-rolled Park–Miller LCG,
`Kibitzer.Rng`), which makes any game a shareable URL.

## What the watcher knows

`Kibitzer.Knowledge` tracks, per player, the cards they certainly hold
and certainly lack; the cards certainly in or out of the envelope; and
a set of live *disjunctions* — "C showed one of {Mrs. White, the Rope,
the Library}" — the public residue of a card being shown.

`Kibitzer.Infer` records each observation's direct consequences, then
runs `saturate`: a fixpoint over named deduction rules —

| Rule | Reading |
|---|---|
| `PassImpliesLacks` | a pass means lacking all three suggested cards |
| `SingletonDisjunction` | a shown-card disjunction narrowed to one candidate |
| `UniqueOwner` | a held card is in no other hand and not in the envelope |
| `HandComplete` | a full hand excludes every other card |
| `LastCandidateHand` | a dealt card only one player can still hold is theirs |
| `EnvelopeByElimination` | a card no player holds is in the envelope |
| `CategoryCount` | one envelope slot per category, counted both ways |
| `EnvelopeExcludesHands` | an envelope card is in no hand |

Termination is by monotonicity: rules only add claims to finite sets or
shrink candidate sets, and nothing is ever retracted, so a pass that
changes nothing is the fixpoint.

Every derived fact carries provenance — the rule, the triggering event,
the show-events it drew on, and the prior facts it consumed (`premises`,
a DAG that is acyclic by construction since facts only cite smaller
ids) — so the UI's feed can say:

```
[E61 · only candidate left] B holds the Billiard Room (resolving the card shown at E2)
```

The **Cascade tab** renders that DAG as animation (Hylograph HATS):
facts fly onto an SVG notebook from the current event, staggered by
derivation depth so chains arrive in logical order; provenance
hairlines flash from premise to conclusion and settle into faint
persistent wiring; unresolved "showed one of these" disjunctions stand
as dashed spines with candidate ticks; and a facts-per-event sparkline
invites scrubbing straight to the avalanches. The animation state is
plain Halogen state driven by `Hylograph.Transition.Tick` — the scene
is rebuilt as pure data every frame, in the same style as everything
else in the app.

The engine is deliberately *sound but not complete*: it propagates, it
does not SAT-solve. We measured exactly what that costs by having Z3
play the **optimal watcher** (`smt/optimal_watcher.py` — the public
transcript as finite-domain constraints; a fact is certain iff its
negation is UNSAT). The first measurement showed a real gap, which two
Sudoku-flavoured counting rules then closed (`DisjunctionCapacity`,
`DisjunctionPigeonhole` — see `Kibitzer.Infer`): the engine now
captures 96–99% of what is logically certain and matches the optimal
watcher's solve rate in six of eight configurations. Z3 agrees with
every certainty it ever emits (an independent soundness check over 800
games), and the board-protects-the-players finding survives even the
perfect adversary (optimal solve rate at six players: 30% classic vs
12% with the board). Details in `docs/formal-methods-follow-on.md`.
The soundness half is what the demo needs — the notebook never lies —
and it is machine-checked:

## The theorems (property tests)

Over random seeds and table sizes, at **every** prefix of the log
(`core/test/Test/PropSpec.purs`):

1. **Soundness** — every fact any perspective infers is true of the
   actual hidden deal; every live disjunction is satisfied by the real
   hand.
2. **Monotonicity** — knowledge only grows along the log.
3. **Player ⊇ watcher** — public inference is a lower bound on every
   player's private knowledge.
4. **Fixpoint** — `saturate` is idempotent; every game ends in a
   correct accusation.

Plus golden tests pinning the seed-42 transcript and the watcher's
final notebook (96 events, 70 facts, ten cards placed exactly, no card
seen).

## Simplifications, stated plainly

- In classic mode there is **no board, dice, or movement** — any player
  may suggest any triple on their turn. The spatial game is chrome; the
  information game is the subject. (The movement variant below restores
  the spatial constraint.)
- Refutation is standard: players are queried clockwise from the
  suggester's left; the *first* holder shows one card, privately;
  players beyond the shower reveal nothing.
- The stock policy suggests uniformly at random (it may probe with its
  own cards — realistic, and useful noise), shows a random refuting
  card, and accuses exactly when its knowledge determines the envelope.
- A correct accusation teaches the watcher nothing: the demo is about
  what was known *before* the reveal.

## The movement variant

Real Cluedo makes you *be in the room you name*: you roll dice, walk the
corridors, and suggest only on arrival. The `movement: true` variant
(`--moves` on the CLI, the Board toggle in the web app) restores that
constraint over a stylised board — nine rooms on a 3×3 grid with the
classic corners (Kitchen top-left, Study bottom-right), corridor travel
as a step distance (3·manhattan + 2: adjacent rooms 5 steps, the far
corner 14) against two dice.

The rules as implemented: resting in a room is a *departure obligation* —
on your turn you either accuse (from anywhere), or roll and travel toward
a destination your own notebook still has questions about; entering a
room triggers a suggestion there in the same turn. Committed journeys (no
mid-course retargeting), no secret passages, no dragging the named
suspect's token (seats are deliberately not suspect cards), overshoot
absorbed. Movement is public metadata — the watcher sees every roll and
every token — and the inference engine deliberately learns **nothing**
from it: a token's path is a hunch, not a fact, and the notebook must
never hold hunches. Termination is unthreatened: every roll ≥ 2, so the
longest journey takes at most seven of your turns.

### Does the board help the watcher? (100 seeds per row)

```
players moves   mean-events mean-suggs mean-win-turn watcher-facts env-known/3  solved% unfinished
3       off            81.6       33.9          34.9          54.0         1.0       2%          0
3       on             97.8       23.9          40.6          42.9         1.0       6%          0
4       off            83.9       31.2          32.2          75.7         1.2       9%          0
4       on            107.8       24.6          41.8          66.9         1.3      11%          0
5       off            95.8       32.1          33.1         100.5         1.6      14%          0
5       on            118.8       25.7          43.2          90.9         1.3      13%          0
6       off           107.3       32.7          33.7         125.5         1.9      28%          0
6       on            126.7       25.7          44.0         112.3         1.5      12%          0
```

Two findings. **Table size is the watcher's real ally**: at six players
the watcher fully solves 28% of classic games (2% at three), because
every suggestion sweeps more hands — more passes, more facts, and
six three-card hands fill up fast. **The board mostly protects the
players**: at six players movement more than halves the watcher's
solve rate. Suggestions become scarcer per turn and — more subtly —
room-constrained: players suggest whatever room they could reach, so the
same nearby rooms recur and each pass repeats more of what the watcher
already knew. (At three and four players the effect is small and runs
the other way — longer games give the few hands time to be pinned
down.) Metadata inference thrives on *varied* questions; the board
forces repetitive ones.

## Workspace layout

```
core/      kibitzer-core      pure engine + inference (no Effect outside tests)
example/   kibitzer-example   CLI demo + stats/corpus/trace modes + skylines/orbits emitters
frontend/  kibitzer-frontend  Halogen app (components + Hylograph HATS/simulation views)
smt/       (Python + Z3)      optimal-watcher oracle, worlds-page builder
smoke/     (puppeteer)        four browser suites against the dev server
docs/      plans and write-ups (cascade viewer, componentization, TMS library seam)
```

Within the core, `Kibitzer.Board` holds the movement geometry,
`Kibitzer.Track` replays token positions from the event log (the same
fold drives the tests and the on-screen map), and `Kibitzer.Game`
dispatches between the classic and movement turn loops.

## License

MIT.
