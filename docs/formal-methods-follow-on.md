# Follow-on plan: the same guarantees by other means — SMT, TLA+, Lean

*Status: SMT experiment **done** (results below, 2026-07-13); TLA+ and
Lean still planned.*

## SMT results, round 2: the gap closed (and a theorem earned its keep)

The first measurement (kept below) priced the gap; two new deduction
rules then claimed most of it:

- **`DisjunctionCapacity`** — a player with f free hand slots and f
  pairwise-disjoint unresolved show-disjunctions has every unknown card
  spoken for. Conclusion taken as the *intersection over all* size-f
  disjoint families' candidate unions — see below for why.
- **`DisjunctionPigeonhole`** — two different players each showed from
  the same two-card pool: both cards are in hands, neither in the
  envelope. (The named `ruleUnrefutedSuggestion` turned out to already
  be subsumed: per-card, EnvelopeByElimination + LastCandidateHand
  cover the envelope-or-suggester residual. The real gap was counting.)

After (same corpus recipe, players now also smarter since they share
the engine — game trajectories changed):

```
players  moves  engine-certs  optimal-certs    gap  engine-solved%  optimal-solved%  unsound
      3    off          54.0           56.1    2.1              2%               2%        0
      3     on          42.9           43.8    0.9              6%               6%        0
      4    off          75.7           78.0    2.2              9%               9%        0
      4     on          66.9           68.6    1.7             11%              11%        0
      5    off         100.5          102.0    1.5             14%              14%        0
      5     on          90.9           92.1    1.2             13%              13%        0
      6    off         125.5          128.0    2.5             28%              30%        0
      6     on         112.3          113.9    1.6             12%              12%        0
```

96–99% of optimal, solve rate equal to the perfect watcher in six of
eight configurations, still zero unsound certainties.

**The war story worth keeping**: the first cut of DisjunctionCapacity
used a *greedy* disjoint-family search and passed its unit tests — but
the player-⊇-watcher property test failed roughly one run in three.
The hunt found the mechanism: a better-informed player prunes candidate
pools differently, greedy picks a different (smaller) family, and the
inference silently vanishes for the mind that knew *more*. Even an
exact maximum-family search can't fix it (the conclusion depends on
which family you pick); the provably view-monotone form intersects the
unions over *every* qualifying family — any watcher family survives,
pruned but still disjoint, into every better-informed view. A rule can
be perfectly sound and still break "more information never hurts";
only the property test caught it.

## SMT results, round 1 (before the counting rules)

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

## The behavioral channel (Andrew's question, 2026-07-14): modelling *choices*

Can the watcher gain by modelling what players' suggestion choices
reveal about what *they* know? Three grades, in increasing power:

1. **Classic mode, stock policy: provably zero.** Suggestions are
   uniform random — a choice independent of knowledge carries no
   information about it. Opening the channel requires strategic
   players first (parking-lot item).
2. **Movement mode leaks today.** `chooseDestination` dogfoods the
   player's notebook (heads for rooms whose envelope status they
   haven't settled) — every journey publicly states "my notebook has
   not excluded this room."
3. **Accusation silence — the strong channel, free under any policy
   with a known accusation rule.** Every turn a player does *not*
   accuse says: their private stream does not yet determine the
   envelope. The watcher knows the public part of that stream and the
   inference rules, so silence constrains the identities of privately
   shown cards. Epistemic logic, Muddy-Children flavour.

**"Does it outperform SMT?" dissolves**: SMT is a solver, not a
ceiling. Our Z3 watcher is optimal *for the transcript-only theory*;
each channel is a new policy axiom, and Z3-with-policy-axioms strictly
dominates the current optimal (never fewer certainties). Encoding
challenge: a player's knowledge is a saturation fixpoint — the
tractable version encodes a sound under-approximation (the player's
unit-propagation closure over candidate hidden cards), giving
sound-but-partial silence constraints. The measurable experiment:
optimal-with-silence vs optimal, per config.

**Probabilistic variant**: weight transcript-consistent deals by choice
likelihood under the policy; posteriors beat every deductive watcher on
early-guess curves but never mint a certainty — and a posterior is a
hunch, so it must live in its own display layer ("the watcher's
suspicions"), never in the notebook.

**Casualties**: player ⊇ watcher does not survive as stated (a
behavioral watcher can know things about C's hand that player B
doesn't, by modelling C's silence) — it is a theorem about the
deductive engine only. The demo's moral sharpens to a hierarchy:
content privacy < metadata privacy < behavioral privacy — encrypt the
cards, anonymize the questions, and *when you choose to act* still
testifies.

**Where neural methods enter** (follow-up question, 2026-07-14): not
here yet. With a known policy and a finite deal space, exact-ish
Bayesian inference by weighted deal-sampling is tractable, calibrated,
and explainable — a net only approximates it. NNs win when (a) the
policy is unknown (human players; learn the behavior model from logs),
(b) exact computation dies (nested epistemic reasoning over long
horizons — why poker belief-state agents bolt neural value functions
onto belief reasoning), or (c) you want amortized inference (a small
net imitating the sampler for instant posteriors in the UI). Reference
points: the Hanabi challenge (theory-of-mind benchmark), DeepStack /
ReBeL (belief states + neural values), Cicero (player world-models as
the load-bearing part), van Ditmarsch on Cluedo as dynamic epistemic
logic. So the write-up's ladder gains a second axis: QuickCheck → SMT →
TLC → Lean is *certainty*; random policy → known policy → learned
policy is *world-model*, and neural methods enter at its third rung.
The metric that justifies any of it: watcher win rate — solved strictly
before the winning accusation.

## The Methods tab (page plan, 2026-07-14)

The site never had a concrete plan for showing the other technologies —
just "tabs about PureScript, SMT, Lean etc". The plan is now: one
**Methods** tab structured as the ladder of quantifier strength, each
rung getting the question it answers, its artifact, and where possible
a visualization instead of a table. TLA+/Lean rungs open as honest
stubs until built. The SMT rung's visual candidates, in build order:

1. **Side-by-side twins** (Andrew's form): the same diagram rendered
   twice — our watcher and the Z3-optimal watcher — scrubbed in
   lockstep from precomputed per-position traces for curated seeds
   (~44 literals × ~80 positions ≈ minutes offline per seed). No new
   mark type; the gap is read by comparison, and its sparseness (96–99%)
   is the visible punchline.
2. **The collapsing worlds**: rows = complete deals still consistent
   with the transcript (Z3 model sampling with blocking clauses),
   columns = the 21 cards coloured by location; certainty = a column
   gone monochrome across all worlds. Prototyped with real data in
   `smt/worlds_mock.py` (seed 42 @4p: >1500 → 1484 → 154 worlds; 5
   columns settle — one more than the engine, the gap made visible).
   The "worlds remaining" log strip pairs with the facts sparkline:
   possibilities destroyed vs information gained.
3. **Table ⇄ DAG morph**: the grid's wiring IS the derivation DAG
   (premises, acyclic by id order) with nodes pinned to notebook cells;
   a DAG layout (depth as layers) is a second position map, and the
   Tick pattern morphs between the two by lerping marks. The state view
   and the argument view, shown to be the same object. Later, Z3 unsat
   cores render on the same canvas: the solver's argument beside the
   engine's.

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
