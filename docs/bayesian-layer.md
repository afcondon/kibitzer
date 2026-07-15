# The third column: a Bayesian layer over the worlds

*2026-07-15, after swimming. Andrew: even in the little Cluedo example
there are times we'd be happy to guess before either SMT or the
deductive framework delivers certainty — the Jane St solution, EV
rather than proof. Plan for a probabilistic add-on to the demo.*

**Status: SOMEDAY (Andrew, same day).** With toy players the
behavioral layer isn't really modelling anything — the players *are*
the policy model, so it's self-referential. Merit as a worked example
of the triptych's third panel, but not convincing as inference. Filed,
not scheduled.

**The EV question, answered honestly (same conversation):** is the EV
calculation itself possible without a better player model? Mostly no —
but the decomposition is worth keeping. EV(accuse now) = P(top
hypothesis), computable (Stage A). EV(wait) needs the race hazard,
which splits:

- *"A rival is already certain"* **is computable from the worlds set
  alone**: within each surviving world the rival's hand is fixed and
  the history is observed, so their notebook is deterministic — run
  the engine from their perspective inside each world and count the
  worlds where they've solved. No suggestion-policy model needed; ≤
  cap×rivals engine replays. The one assumption it does embed: rivals
  are perfect logicians running *our* rule set.
- *"A rival becomes certain within k moves"* needs future events,
  which needs their suggestion policy — the toy-player circularity
  again, irreducibly.

So the only honest EV is horizon-one ("accuse now vs. survive one more
round") conditional on perfect-logician rivals; the general optimal
stopping of Stage D is not recoverable without real player models.
Andrew's instinct correct: the hazard is the part the model can't
fake.

## Why it completes the picture

The correspondence table (smt-jtms-brainstorm.md §3) gains its natural
third column — the old trinity of proof, model, and measure:

| | JTMS (engine) | SMT (Z3) | Bayes |
|---|---|---|---|
| certainty is | derivability ⊢ | entailment ⊨ | posterior P > θ |
| the object | derivation DAG | surviving-model set | distribution over models |
| its dynamics | facts accrete | worlds die | mass concentrates |
| the explanation | premise ancestry | unsat core | which events carried the bits |
| the verdict | proof | proof | a *bet*, with a price |

Two structural gifts mean this is not a bolt-on:

1. **The worlds canvas is already the posterior.** Under a uniform
   prior over deals (correct: envelope uniform over 6·6·9, every
   partition of the remaining 18 into the fixed hand sizes equally
   likely), the posterior over envelope triples is literally *counting
   surviving worlds*. The enumeration the worlds pages already compute
   is the exact posterior support; the pastel rows are samples from
   it.
2. **The log-paper chart is the entropy curve in disguise.** log₂ of
   the world count *is* the watcher's uncertainty in bits (uniform
   case); each event's drop is the information it carried. Seed 33's
   E73 killing 765 of 880 worlds is a ~2.9-bit event. The chart we
   ship is already an information-theoretic object — the Bayesian
   layer just says so out loud.

The caveat that becomes Stage C: uniform-over-survivors is the exact
posterior **only if the likelihood of the observed history is equal
across all consistent worlds** — i.e. only if players' *choices* leak
nothing. They do leak (below). Stages A–B are the honest uniform
approximation; Stage C is where EV genuinely beats deduction.

## Stage A — exact posterior from p0 onward (nearly free)

From the first enumerable position (p0 = E66 at seed 33/6p) we hold
the complete surviving-world set. Per position:

- P(envelope = (s,w,r)) = |worlds with that triple| / |worlds| — a
  histogram over ≤ 324 triples, computed in the replay loop we already
  have (`worlds_trace.py` pure evaluation; no new solver calls).
- Track the max-posterior triple and its P; find the first position
  where P(top) crosses θ ∈ {0.5, 0.8, 0.9, 0.95}.

**The headline artifact**: "the watcher could have *bet* the solution
at E__ with 92% confidence — N events before either framework could
*prove* it." On seed 33 the collapse tail (…→ 12 → 6 → 2 → 1) means
the 2-world position is already a coin flip between two triples — if
they differ only in one card, P(top) may be high much earlier. Worth
measuring across the ten probed seeds: the θ-crossing vs proof-moment
gap is the whole pitch, and we don't yet know how big it is.

Viz: a P(top hypothesis) line on the existing log chart (second
y-axis, 0–1), with θ-crossings marked the same way solve moments are;
a belief bar (top-k triples with their masses) beside the BIG NUMBER.

## Stage B — the pre-p0 region (genuinely hard; be honest)

Before p0 the world set is unenumerable (~4.4×10¹³ at the deal) and
we currently show the estimated count. For *marginals* the options,
in order of preference:

1. **DP over hand capacities + inclusion–exclusion.** Fixing an
   envelope triple, counting deals consistent with the *unary*
   constraints (card ∉ hand, card ∈ hand) is a small dynamic program:
   process cards in sequence, state = remaining capacity vector
   (≤ ∏(hᵢ+1) ≈ 10³ states, 18 cards — trivial). The disjunctive show
   constraints ("shower holds ≥1 of these 3") break independence;
   inclusion–exclusion over the *unresolved* shows handles ≤ ~20 of
   them (2²⁰ DP runs of microseconds each). Early game has few
   unresolved shows, late game has few — the bulge in the middle is
   the risk; measure it before committing.
2. **Hash-based near-uniform sampling** (UniGen-style XOR constraints
   through Z3) if the bulge is too fat for inclusion–exclusion.
3. **What does NOT work**: naive rejection sampling (deal, check
   consistency). Acceptance = surviving/total ≈ 10⁻¹⁰ by mid-game —
   it dies long before enumeration becomes feasible, so there is no
   clean rejection→enumeration crossover. A particle filter without
   principled rejuvenation degenerates the same way, only slower.

Stage B is optional for the demo: Stage A alone (posterior from p0)
already tells the EV story. Do B only if the θ-crossing turns out to
sit before p0 on interesting seeds.

## Stage C — behavioral likelihoods (the actual Jane St layer)

Pure counting treats P(history | world) as constant across consistent
worlds. False in general: players' *choices* are informative.

- A player who never suggests cards she holds leaks with every
  suggestion — before any show or pass touches the constraint set.
- Which player shows (first in order holding a match) is deterministic
  given the world, but *which card* a multi-match shower picks, and
  which rooms a player steers toward, follow policies conditioned on
  private knowledge.

Weighting each surviving world by P(observed choices | world, policy
model) is importance-weighting the enumeration — rows in the canvas
gain weights (render as brightness), and the posterior sharpens on
evidence the logical layers *cannot see at all*. This is the stage
where the EV watcher isn't just earlier-with-confidence but is
reading different information: the table, not just the cards.

Honest risk: it requires committing to a policy model of the simulated
players, and our players *are* the policy model — so it risks
circularity (perfect policy knowledge = more inference than a real
watcher has). Mitigation: use a deliberately weakened policy model
(e.g. "suggests uniformly among cards not held") and report
sensitivity.

## Stage D — the decision layer (light touch)

θ is arbitrary; the principled version is optimal stopping. In Cluedo
a wrong accusation eliminates you, so the bet has a price: EV(accuse
now) = P(top), vs EV(wait) discounted by the risk a rival accuses
first. We have the engine's per-player solve times per seed — an
empirical rival-hazard curve. One chart: P(top) rising vs the hazard
of waiting, crossing at the optimal accusation moment. Keep it to one
chart; the demo is about the three columns, not game theory.

## Sequencing and scope

- Stage A first — it's replay-loop arithmetic plus chart work, and it
  produces the measurement (θ-crossing vs proof gap) that tells us
  whether B–D earn their keep.
- This *extends* the demo's scope decision (QuickCheck + SMT, no
  TLA+/Lean): the Bayesian layer is cheap where those rungs were
  expensive, and it lands on the pages we already built rather than
  demanding new ones.
- Library angle, noted not planned: the counting/weighting machinery
  is the seed of a third correspondence partner (⊢ / ⊨ / P) — but the
  rule-of-three hunt for a *probabilistic* library client starts only
  if Stage C proves out here.
