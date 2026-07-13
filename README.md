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
make bundle serve # web app on http://localhost:3077 (?seed=N is shareable)
```

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
does not SAT-solve. A cleverer watcher could squeeze out a little more
(e.g. reasoning across overlapping disjunctions, or from suggestions
nobody could refute). The soundness half is what the demo needs — the
notebook never lies — and it is machine-checked:

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

- **No board, dice, or movement** — any player may suggest any triple
  on their turn. The spatial game is chrome; the information game is
  the subject.
- Refutation is standard: players are queried clockwise from the
  suggester's left; the *first* holder shows one card, privately;
  players beyond the shower reveal nothing.
- The stock policy suggests uniformly at random (it may probe with its
  own cards — realistic, and useful noise), shows a random refuting
  card, and accuses exactly when its knowledge determines the envelope.
- A correct accusation teaches the watcher nothing: the demo is about
  what was known *before* the reveal.

## Workspace layout

```
core/      kibitzer-core      pure engine + inference (no Effect outside tests)
example/   kibitzer-example   CLI transcript demo (spago run -p kibitzer-example -- 42)
frontend/  kibitzer-frontend  Halogen split-screen app (spago bundle → public/)
```

## License

MIT.
