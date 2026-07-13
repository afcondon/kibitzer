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

spago run -p kibitzer-example -- 42 --moves --players 6   # any variant, as text
spago run -p kibitzer-example -- stats 100                # the comparison table
```

Web-app URLs carry the whole configuration — `?seed=42&players=6&moves=1`
reproduces a game exactly.

The dev URL `http://localhost:3026` is Bosun-routed (registered as
`kilo-papa-zulu-delta:frontend` in Bosun's fleet registry; Marginalia
project #251) — `bosun serve` lazy-spawns the static server on first
request, so `make serve` is only needed when the router isn't running.

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

Every derived fact carries provenance — the rule, the event that
triggered it, and (for resolved disjunctions) the original show-event —
so the UI's feed can say:

```
[E61 · only candidate left] B holds the Billiard Room (resolving the card shown at E2)
```

The engine is deliberately *sound but not complete*: it propagates, it
does not SAT-solve. We measured exactly what that costs by having Z3
play the **optimal watcher** (`smt/optimal_watcher.py` — the public
transcript as finite-domain constraints; a fact is certain iff its
negation is UNSAT). Over 800 games: the engine captures 92–96% of what
is logically certain, Z3 agrees with every one of its ~78k certainties
(an independent soundness check), and the board-protects-the-players
finding survives even the perfect adversary (optimal solve rate at six
players: 40% classic vs 24% with the board). Details in
`docs/formal-methods-follow-on.md`. The soundness half is what the demo
needs — the notebook never lies — and it is machine-checked:

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
3       off            82.8       34.4          35.4          54.0         0.9       2%          0
3       on             99.1       24.3          41.1          43.0         0.9       6%          0
4       off            86.5       32.2          33.2          74.2         1.1       6%          0
4       on            109.6       25.0          42.6          65.3         1.2      10%          0
5       off            98.8       33.1          34.1          98.7         1.6      14%          0
5       on            122.2       26.4          44.7          85.6         1.1       7%          0
6       off           109.8       33.4          34.4         121.7         1.8      31%          0
6       on            132.4       26.9          45.8         108.7         1.3      12%          0
```

Two findings. **Table size is the watcher's real ally**: at six players
the watcher fully solves 31% of classic games (2% at three), because
every suggestion sweeps more hands — more passes, more facts, and
six three-card hands fill up fast. **The board mostly protects the
players**: at five and six players movement roughly halves the watcher's
solve rate. Suggestions become scarcer per turn and — more subtly —
room-constrained: players suggest whatever room they could reach, so the
same nearby rooms recur and each pass repeats more of what the watcher
already knew. (At three and four players the effect is small and runs
slightly the other way — longer games give the few hands time to be
pinned down.) Metadata inference thrives on *varied* questions; the
board forces repetitive ones.

## Workspace layout

```
core/      kibitzer-core      pure engine + inference (no Effect outside tests)
example/   kibitzer-example   CLI transcript demo + stats mode
frontend/  kibitzer-frontend  Halogen split-screen app (spago bundle → public/)
```

Within the core, `Kibitzer.Board` holds the movement geometry,
`Kibitzer.Track` replays token positions from the event log (the same
fold drives the tests and the on-screen map), and `Kibitzer.Game`
dispatches between the classic and movement turn loops.

## License

MIT.
