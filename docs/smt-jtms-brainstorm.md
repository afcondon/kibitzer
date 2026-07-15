# Before the bow: TLA+/Lean, SMT-library clients, and the JTMS ⇄ SMT correspondence

*2026-07-15, thinking session with Andrew after the worlds canvas
landed. Three threads: what the remaining ladder rungs were for and
what they'd be now; who the clients of a PureScript SMT library would
be (rule of three); and the correspondence between the JTMS and SMT
"type systems" that kibitzer now demonstrates operationally.*

## 1. The remaining rungs: TLA+ and Lean, revisited

The original ladder (formal-methods-follow-on.md): QuickCheck samples
∃-many games, SMT decides one game completely, TLC decides all *small*
games, Lean decides all games. SMT is done and paid off twice (the
completeness measurement; the worlds pages). What the other two rungs
were, plus what they'd be **now** that the observatory exists:

**TLA+ / TLC** — model the game as a nondeterministic state machine
over a reduced deck (2 suspects × 2 weapons × 2 rooms, 3 players) and
let TLC exhaust *every* possible tiny game — deals, dice, and policy
choices all ∃-quantified. Invariants: soundness, monotonicity,
watcher ⊆ player, termination as liveness. What it buys that sampling
can't: the adversarially unlucky interleavings QuickCheck would
essentially never hit.

New thinking since the worlds canvas:

- **The state graph is drawable.** TLC can dump its reachable-state
  graph; for the tiny model that graph is small enough to *render
  completely* — the "all possible games" analogue of the worlds
  canvas (which shows all possible *deals* for one game). A Hylograph
  rendering of the exhausted state space would make the TLA+ rung a
  page, not a table — consistent with the house rule that every rung
  gets a visualization.
- **Model size is driven by which rules you want exercised.** Hand
  size 1 exercises passes/shows/elimination but can never fire
  DisjunctionCapacity (needs ≥2 free slots) — and capacity is exactly
  the rule whose greedy form failed view-monotonicity. The honest
  model is the smallest one where the war-story rule *can* misfire;
  worth sizing before writing any TLA.

**Lean 4** — port the core (small, first-order: enums, Finset,
records) and prove: per-rule soundness by induction over the fold,
monotonicity, `saturate` termination as well-founded recursion (the
code comment becomes kernel-checked), and — the ambitious one — the
player ⊇ watcher simulation argument. Scoped as Lean-1/2/3; stop when
marginal insight drops.

New thinking since the JTMS identification:

- **The proofs attach to the library, not the demo.** If the JTMS
  kernel gets extracted (§3), Lean-1 (termination + soundness of the
  saturation kernel) is a proof about the *library* — every future
  client inherits it. That reorders the economics: Lean-1 after
  extraction is worth much more than Lean-1 before.
- **The crown jewel is view-monotonicity of DisjunctionCapacity** in
  its intersect-over-all-families form — the rule where testing found
  a real bug in a sound rule. A machine-checked proof of the repaired
  form is the best possible advertisement for the whole ladder: each
  rung catching what the one below missed, on the same artifact.

## 2. Clients for a PureScript SMT library (the rule-of-three hunt)

Shape (from tms-library-sketch.md): SBV as the *shape*, not a port —
finite domains, cardinality/pseudo-boolean sums, push/pop, model
harvesting, unsat cores; SMT-LIB text over a child process on Node,
z3-wasm in the browser. Candidate clients across the ecosystem, in
rough order of conviction:

1. **Kibitzer** (exists — the requirements document). Everything in
   `smt/optimal_watcher.py` and `smt/worlds_trace.py`, in-process:
   the live oracle ("ask Z3" at any position), unsat cores rendered
   as the solver's argument beside the engine's derivation DAG.
2. **FH-2 / ES-9 auto-routing** (the sleeper favourite). "Assign
   voices/CV/gates/clocks to converters and outputs subject to
   hardware constraints" is a textbook finite-domain CSP on Andrew's
   actual rig: adjacency constraints (pitch/gate pairs), exclusions,
   channel capacities. es9-config and fh2-config already own the
   typed models; the solver turns them from *editors* into
   *configurators* ("I want these eight voices — find me a routing").
   Real pain, real hardware, honest constraints.
3. **ShapedSteer** (the designated second client for JTMS; SMT is its
   global-search complement). Plan feasibility over typed DAGs:
   executor assignment under capability/resource constraints,
   schedule consistency, "is there any assignment at all" (sat),
   "why not" (core), incremental what-if via push/pop.
4. **Voice-leading / harmony** (the delightful demo; joins the music
   domain to the library). Minimal-motion voicing subject to range,
   spacing, and doubling rules; quantiser scale selection (Harmonia);
   tarot-music's card-constraints → key/mode/chord with global
   consistency. Classic constraint-programming territory.
5. **Hylograph constraint layout** (the Penrose-flavoured showcase).
   Alignment/non-overlap/ordering constraints as an alternative to
   force layouts for small diagrams — Penrose proved diagram layout
   by constraint solving is viable; a Hylograph binding would be a
   showcase and a genuinely different layout engine.

   *Sharpened 2026-07-15 (Andrew: "a GraphViz replacement that
   doesn't involve porting C++ to WASM?").* Two-part answer. (a) The
   no-port candidate for dot's bread-and-butter is a **pure PureScript
   Sugiyama** (rank / order / position / route) in hylograph-layout —
   dagre and d3-dag prove the pipeline is ~2–3k lines of portable
   algorithm code, no C++ anywhere; clients in-house (Minard,
   ShapedSteer DAG views, the skyline family). (b) What **SMT** adds
   is not scale but *exactness and explainability at small scale*:
   rank assignment and crossing minimization as MaxSMT (exact minimum
   crossings; user constraints like "keep these aligned" composed
   into the same solve, which dot cannot do), and — the kibitzer
   move — an **unsat core when the layout constraints conflict**,
   instead of GraphViz's silent weirdness. Orders of magnitude slower
   than dot, so it's for small explanatory diagrams — exactly
   Hylograph's register. Browser honesty: z3-wasm is itself a C++
   port, but consuming Microsoft's maintained artifact ≠ porting one;
   Node-side it's a clean child process.
6. Long tail: puzzle showcases with unsat-core explainers (Sudoku
   "why is this cell forced" — the kibitzer argument view, reused);
   Bosun placement/port allocation (real but small); dependency
   conflict explainers.

**What the client list does to the API** — the important outcome:
clients 2 and 4 both need *optimization*, not just satisfaction
(minimal voice motion; preferred routings as soft constraints). So
the core subset grows one member the kibitzer-only view missed:
**Optimize / MaxSMT (soft asserts, minimize/maximize)**. Z3 has it;
SBV has it; without it the two most attractive clients fall out.
Requirements from real clients, exactly as hoped.

Rule of three: kibitzer (exists) + FH-2 routing + ShapedSteer would
satisfy it, with voice-leading as the demo that makes the README sing.

## 3. The JTMS ⇄ SMT correspondence, made explicit

Kibitzer is now an operational demonstration of the oldest duality in
logic: **proof theory vs model theory**, ⊢ vs ⊨.

| | JTMS (the engine) | SMT (Z3) |
|---|---|---|
| certainty is | derivability ⊢ (a chain of rule firings) | entailment ⊨ (negation unsat) |
| the object | the derivation DAG (orbits, skylines) | the surviving-model set (worlds canvas) |
| its dynamics | facts accrete, DAG grows | worlds die, set shrinks |
| the explanation | premise ancestry (hover) | unsat core |
| in the literature | Doyle 1979 (JTMS) | de Kleer 1986 (ATMS = model sets per environment) |

Soundness is ⊢ ⊆ ⊨ — measured: zero unsound certainties across ~78k.
Incompleteness is ⊢ ⊊ ⊨ — *visible*: the dot-without-a-ring on the
worlds-gap page is a card the models agree on that no derivation
chain reaches. And the gap has a proof-theoretic character: our rules
are Horn-ish unit propagation, and what they miss is **counting** —
pigeonhole reasoning, which resolution famously cannot do in
polynomial size (Haken 1985). DisjunctionCapacity and
DisjunctionPigeonhole are hand-added axiom schemas compensating for
exactly that classical weakness. The completeness gap of the engine
is a live exhibit of the proof-complexity literature.

**The Curry-Howard-flavoured reading** (Andrew's "type systems"):
a kibitzer fact `{claim, justification: {rule, premises}}` *is* a
proof term — claim as proposition, rule as inference-rule name,
premises as sub-proofs, the DAG as the proof forest. The JTMS eDSL is
therefore a small proof-term kernel with rules-as-data; the Lean port
would make this literal (each rule an inductive constructor, soundness
an interpretation into semantics). The orbit view is, quite exactly,
a proof-tree visualizer.

**Where the two libraries meet — the concrete design insight**: the
JTMS library's property-test kit needs an oracle to state soundness
and completeness against; the SMT library *is* that oracle. The
interface between the pair is one record:

```purescript
type Oracle claim =
  { certain :: Array Constraint -> claim -> Boolean   -- ⊨?
  , explain :: Array Constraint -> claim -> UnsatCore -- why
  }
```

kibitzer's PropSpec + optimal_watcher.py is the existing prototype of
exactly this interface, run over a JSON side channel. The library
pair is co-designed: JTMS provides ⊢ with provenance, SMT provides ⊨
with cores, the test kit checks ⊢ ⊆ ⊨ and *prices* ⊢ ⊊ ⊨, and — for
claims in the shared Horn fragment — a translator can replay an unsat
core into a derivation DAG, rendering the solver's argument in the
engine's visual language. `explain :: claim -> Either UnsatCore
DerivationDag` is the API where the correspondence stops being an
essay and becomes a function.

## Decisions and revisions (same day)

- **Scope: the Cluedo demo stops at QuickCheck + SMT** (Andrew).
  TLA+/Lean remain designs; if ever built, against the extracted
  library, not the demo.
- **Harmonia is a JTMS client, not an SMT client** (Andrew's hunch,
  sharpened): music *analysis* is monotone deduction — facts about a
  score/stream derived by named rules with premises. Three concrete
  shapes:
  1. **Explainable scale/key inference from a note stream** — this is
     kibitzer-isomorphic: notes arriving = events, candidate
     scales/keys = worlds, each note eliminates candidates
     (Lacks-shaped), ambiguity is a live disjunction ("A minor or
     C major") that later notes resolve, and provenance answers "why
     does the quantiser think we're in D dorian." An explainable,
     incremental quantiser brain for Harmonia/the Dáil work.
  2. **Counterpoint/voice-leading linting with provenance** — rules as
     data ("parallel fifths, S against B, bar 3, because…"), species
     counterpoint as the canonical declarative rule set; testable,
     user-extensible at the eDSL level.
  3. Analysis facts generally (common tones, suspensions, cadence
     identification) accreting monotonically over a score.
  The executable stays small and fast because it is saturation, not
  search — monotone unit propagation is real-time-friendly (the live
  rig could run it against the MIDI stream). Where *search* is truly
  needed (choose the best voicing), generate-and-test with the JTMS
  as judge — or the SMT sibling, offline. The division of labour is
  the ⊢/⊨ split again: JTMS explains and validates fast; SMT searches
  and optimizes.
- **Rule of three, both libraries, now satisfied on paper**:
  JTMS — kibitzer, ShapedSteer, Harmonia.
  SMT — kibitzer, ShapedSteer, FH-2 auto-routing (plus possibly a
  second contrived puzzle example; Andrew is open to one).
- **A Bayesian layer joins the plan** (Andrew, 2026-07-15, after
  swimming): guess before either ⊢ or ⊨ delivers certainty — EV
  rather than proof, "the Jane St solution". The correspondence table
  gains its third column (⊢ / ⊨ / P: proof, model, measure); the
  worlds canvas is already the uniform posterior and the log chart is
  already the entropy curve in bits. Staged plan in
  `docs/bayesian-layer.md` — Stage A (exact posterior from p0,
  nearly free) first; it measures the θ-crossing-vs-proof gap that
  decides whether the later stages earn their keep.
- Next build steps, revised: (a) FH-2 auto-routing spike against z3
  (second SMT client in its habitat; prices Optimize/MaxSMT); (b) a
  Harmonia scale-inference spike using kibitzer's saturation pattern
  by hand (second JTMS client; prices the kernel API); extraction
  when either spike starts wanting the shared kernel.

## The halfway house (Andrew, on Curry-Howard)

The Cluedo program sits between types and proofs, and that middle rung
has a name worth keeping: **proof-carrying data, testably sound**. The
fact records are proof terms — but checked dynamically (QuickCheck
properties + the SMT oracle audit) rather than statically (a kernel).
More than types: every fact carries its evidence and can be asked
"why". Less than Lean: the evidence is audited, not machine-checked.
The observatory is then a *proof renderer* — orbits draw ⊢, worlds
draw ⊨ — which is what makes the thing a tool for thought rather than
just a demo: the artifacts you manipulate on screen are arguments.
