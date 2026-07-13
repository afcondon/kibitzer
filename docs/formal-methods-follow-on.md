# Follow-on plan: the same guarantees by other means — SMT, TLA+, Lean

*Status: SMT experiment **done** (results below, 2026-07-13); TLA+ and
Lean still planned.*

## SMT results (800 games: seeds 1–100 × players 3–6 × movement off/on)

`spago run -p kibitzer-example -- corpus 100 > smt/corpus.jsonl`, then
`smt/optimal_watcher.py` (Z3, ~43s for all 800 games):

```
players  moves  engine-certs  optimal-certs    gap  engine-solved%  optimal-solved%  unsound
      3    off          54.0           57.2    3.2              2%               2%        0
      3     on          43.0           44.8    1.8              6%               6%        0
      4    off          74.2           80.1    5.9              6%              11%        0
      4     on          65.3           70.7    5.4             10%              12%        0
      5    off          98.7          103.7    5.0             14%              17%        0
      5     on          85.5           94.1    8.5              7%              16%        0
      6    off         121.7          130.3    8.6             31%              40%        0
      6     on         108.7          119.1   10.4             12%              24%        0
```

Four things this bought us:

1. **An independent soundness check.** Across 800 games and ~78,000
   engine certainties, Z3 disagreed with **zero** — a completely
   different technology re-deriving every claim the notebook ever made.
2. **The completeness gap is small.** The propagation engine captures
   92–96% of what is logically certain; the perfect watcher gains only
   ~2–10 extra certainties per game. Sound-but-incomplete was the right
   trade.
3. **The gap lives where predicted.** It is largest in movement games
   (10.4 at 6p) — the unrefuted-suggestion residual and
   cross-disjunction reasoning our local rules skip. That prices
   `ruleUnrefutedSuggestion` before writing it: at six players with the
   board, it (plus friends) is worth roughly a doubling of solve rate
   (12% → 24%).
4. **The headline finding survives the stronger adversary.** Even the
   *optimal* watcher solves fewer board games than classic games at
   large tables (40% vs 24% at 6p) — so "the board protects the
   players" is a property of the information flow, not an artifact of
   our engine's incompleteness.

## The question

Kibitzer's correctness story is four QuickCheck properties (soundness,
monotonicity, player ⊇ watcher, fixpoint/termination) checked over
random games, plus pinned goldens. Sampling gives high confidence but
no certainty, and it can only answer questions you can phrase as "run a
game and check". Three other technologies are worth trying against the
same problem — not because the FP tests are weak, but because each
answers a **different kind of question**:

| | question it answers | scope | est. effort | what's new |
|---|---|---|---|---|
| QuickCheck (have it) | "does it hold on thousands of random games?" | sampled, full size | hours (done) | statistics: solve rates, fact counts |
| **SMT / Z3** | "what is the *best possible* watcher for this game?" | per game, exact | an afternoon | the completeness gap of our rules |
| **TLA+ / TLC** | "does it hold for *every possible* small game?" | exhaustive, reduced deck | 1–2 days | corner cases sampling may never hit |
| **Lean 4** | "is it a *theorem* — all decks, all logs?" | universal | days–weeks | certainty; termination proof machine-checked |

Honest answer to "would they give an answer *faster*?": for the
statistical questions (solve rates by table size, the movement effect)
**no** — simulation is the only tool that answers those at all, and it
was same-day. But the SMT experiment answers a question the FP harness
*cannot*, in less code than one of our spec files; and Lean turns the
comment-with-an-argument about `saturate` termination into a checked
proof.

## 1. SMT: the optimal watcher (recommended first — genuinely new information)

Cluedo is a finite-domain constraint problem: 21 cards, each in exactly
one of N hands or the envelope. Our inference engine is *sound but
deliberately incomplete* (it propagates, it doesn't search). Z3 can
play the **maximal sound watcher**: everything that is logically
certain given the public transcript, including reasoning our rules
miss (cross-disjunction interactions, unrefuted-suggestion residuals,
counting arguments).

**Encoding** (tiny — Booleans only):

- Variables: `place[c] ∈ {A..F, Env}` per card (or one-hot Booleans).
- Deck axioms: each card exactly one place; envelope exactly one card
  per category; `|hand p| = handSizes(p)` (pseudo-Boolean counting).
- Per public event: `Passed p sugg` → the three cards' places ≠ p;
  `CardShown by _ sugg` → at least one of the three is placed at `by`.
  (That is the *whole* watcher view — the shown card's identity never
  enters.)
- A literal L (e.g. `place[Rope] = Env`) is **certain** iff
  constraints ∧ ¬L is UNSAT. ~44 queries per position, milliseconds
  each.

**Deliverables**

1. `--json` flag on the example CLI: dump `{playerCount, handSizes,
   publicEvents}` (no ground truth beyond what the watcher sees; keep
   the solution in a separate field for scoring only).
2. `smt/optimal_watcher.py` (~150 lines, `pip install z3-solver`):
   reads the JSON, prints the optimal certain-facts grid, optionally
   per position.
3. `smt/compare.py`: over seeds 1..100 × the 8 configs, report
   **optimal solve%** vs our watcher's (prediction: meaningfully above
   31% at 6p classic) and the mean **completeness gap** (facts the
   optimal watcher has that ours lacks).
4. A short section in the About tab / README with the measured gap —
   "how much does the kibitzer leave on the table?"

**Bonus**: the SMT oracle doubles as a differential-test oracle if we
ever implement `ruleUnrefutedSuggestion` — its value can be quantified
before writing it.

## 2. TLA+: exhaustive checking of a small model

Model the game as a nondeterministic state machine — dice outcomes and
policy choices become `∃` (TLC explores *all* of them, not a sampled
policy). Check as invariants over **every reachable state**:

- `Sound` — every derived fact true of the chosen deal (deal is also
  nondeterministic: TLC quantifies over all deals).
- `Monotone` — knowledge sets never shrink (as an action property).
- `WatcherLB` — watcher's definite sets ⊆ every player's.
- Termination as a liveness property under fairness.

**The necessary compromise**: full Cluedo (21 cards, 4 players) is far
beyond TLC. Use a reduced deck — 2 suspects × 2 weapons × 2 rooms,
3 players, hand size 1 — small enough to exhaust, large enough that
passes, shows, disjunction resolution, and elimination all occur. The
claim it buys: *for every possible tiny game, including adversarially
unlucky interleavings sampling would essentially never hit, the
invariants hold.*

**Deliverables**: `tla/Kibitzer.tla` (state: hands, envelope, per-mind
knowledge as sets; `Saturate` as a recursively-defined operator or an
inlined closure), `tla/Kibitzer.cfg`, a README note on what the small
model does and does not establish.

## 3. Lean 4: the theorems as theorems

Port the core (it is small and purely first-order: enums, `Finset`,
records) and prove universally:

- **Soundness**: by induction over the observation fold, one lemma per
  deduction rule ("if the premises are true of the deal, the derived
  claim is").
- **Monotonicity**: each rule only inserts; `learn` never removes.
- **`saturate` terminates**: the monotone-measure argument that today
  lives in a code comment becomes a well-founded recursion the kernel
  checks. This is the single most satisfying upgrade.
- **Player ⊇ watcher** (the ambitious one): a simulation argument
  between observation streams — the watcher's stream is pointwise less
  informative, and `learn` is monotone in information.

**Scoping** (do not attempt all at once): Lean-1 = types + `learn`
soundness for passes/shows + saturate termination; Lean-2 = full rule
set; Lean-3 = the superset theorem. Each milestone is independently
valuable; stop when the marginal insight drops.

**Deliverables**: `lean/` Lake project, `Kibitzer/Basic.lean`,
`Kibitzer/Soundness.lean`; README section mapping each QuickCheck
property to its theorem (or its "still sampled" status).

## Suggested order and why

1. **SMT** — smallest program, answers a question we cannot currently
   answer, produces a number for the About page.
2. **TLA+** — exhaustive assurance for the protocol mechanics, and the
   most transferable skill demo (specification thinking).
3. **Lean** — the gold standard, undertaken knowing the cost; even
   Lean-1 alone (termination + partial soundness) is a worthwhile
   endpoint.

A closing observation for the eventual write-up: the four technologies
form a ladder of *quantifier strength* — QuickCheck samples ∃-many
games, SMT decides one game completely, TLC decides all small games,
Lean decides all games — and the FP implementation is what every rung
leans on: the types and the event-log design port directly to all
three.
