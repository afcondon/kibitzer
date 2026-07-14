# The TMS in kibitzer — a library seam, sketched

*2026-07-14, after Andrew recognized Doyle's Truth Maintenance System
in the DAG skyline. Not to be extracted yet — this documents the seam
so the cut is clean when a second client (ShapedSteer) demands it.*

## The identification

Kibitzer's engine is a **monotone JTMS** (Doyle 1979): beliefs with
justifications (`{rule, source, origins, premises}` ≈ Doyle's
justification structure), a growing dependency network, first
justification wins. We lack — because Cluedo never needs — retraction
and non-monotonic justifications, i.e. all of the machinery that made
TMSs hard (dependency-directed backtracking).

The SMT contrast is the field's own history: JTMS reasons through
justification chains (incremental, auditable, human-style); de Kleer's
**ATMS** (1986) reasons over all environments at once because chains
provably miss things — exactly our completeness gap (the counting
rules local propagation missed and Z3 caught). The derivation DAG is
the JTMS view; the collapsing-worlds matrix is the ATMS view; the
Methods tab will show both. Primary source with working code: Forbus &
de Kleer, *Building Problem Solvers* (1993).

## The four layers (decreasingly domain-specific)

1. **Saturation kernel** — monotone rules over a knowledge base,
   Eq-fixpoint, dedup, premises acyclic by id-ordering. Generic over
   the claim type; the domain contributes a `Claim` ADT + rules.
   Today: `Kibitzer.Knowledge` + `Kibitzer.Infer`'s `saturate`.
2. **Provenance/cascade model** — frames, per-frame depths, the
   premise DAG. Nearly domain-free already (`Kibitzer.Cascade`).
3. **Property-test kit** — soundness-against-oracle, monotonicity,
   fixpoint termination, and **view-monotonicity** (the player ⊇
   watcher theorem): the subtle one — a rule can be sound yet violate
   "more information never hurts" (the greedy-capacity war story), and
   only the cross-perspective property catches it. Any multi-executor
   system wants this as a reusable combinator.
4. **Visualization pair** — the grid ⇄ DAG morph and the cascade
   animation, over layer 2's frame model (Hylograph component
   candidates).

## The ShapedSteer fit

A typed-DAG workbench with human and AI executors needs justification-
carrying facts natively: "why does this node hold", "what breaks if
this input is retracted", "does executor A's conclusion survive into
B's better-informed view" (= view-monotonicity across an executor
lattice). ShapedSteer is also where **retraction finally matters**
(invalidated AI outputs, human overrides) — the second client would
push the kernel from our monotone special case toward full Doyle, and
the planned Bayesian layer pushes the same direction.

## The pair of libraries (Andrew, 2026-07-14)

Two PureScript libraries, both eDSLs, both natural Hylograph clients:

1. **The JTMS library** — layers 1–3 above. As an eDSL: rules declared
   as data (name + premises pattern + conclusion), with provenance
   capture, saturation, and the property-test kit generated from the
   declarations. Rules-as-data also buys generic tracing/profiling and
   lets the DAG visualization label any domain's rules for free.
2. **The SMT library** — the Haskell reference is **SBV** (SMT Based
   Verification, Erkök): a typed symbolic eDSL (`SBool`, `SInt`,
   `prove`/`sat`) over SMT-LIB. Counsel: port the *shape*, not the
   codebase — SBV leans hard on Haskell-specific type machinery, and
   kibitzer's actual needs are a small clean subset: finite domains,
   cardinality/pseudo-boolean sums, push/pop, model harvesting, unsat
   cores. Backend: SMT-LIB text over FFI (z3 as child process on Node;
   z3-wasm in the browser for the live-oracle flex). Kibitzer's
   `optimal_watcher.py` is the requirements document — port it as the
   library's first client and the API writes itself.

The Hylograph fit is the same for both: each produces an inherently
visualizable structure (justification DAGs; model sets / unsat cores),
and kibitzer already renders prototypes of each (the skyline; the
collapsing worlds).

## Timing

Rule of three (or at least two): extract when ShapedSteer reaches for
it, against two real clients, not before. Until then: keep kibitzer's
core boundary clean (it is), and let the Methods tab write-up carry
the JTMS/ATMS framing publicly.
