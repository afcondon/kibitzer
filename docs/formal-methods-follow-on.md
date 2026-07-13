# Follow-on plan: the same guarantees by other means — SMT, TLA+, Lean

*Status: planned, not started. 2026-07-13.*

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
