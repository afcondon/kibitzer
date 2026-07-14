# Browser smoke suites

Puppeteer checks against the dev server on `:3026` (Bosun-served, or
`make serve`). They assume a local Chrome at the standard macOS path
and `puppeteer-core` resolvable from `/Users/afc/node_modules` — these
are personal-rig scripts, not portable CI.

```sh
node smoke/cascade-smoke.mjs    # the grid view: chrome, marks, wiring, scrub, tab roundtrip (18 checks)
node smoke/packs-smoke.mjs      # possibility packs: 147 bubbles, envelope, orbits, view swap (12)
node smoke/dag-smoke.mjs        # the table ⇄ DAG morph: positions, chrome fade, axis, restore (11)
node smoke/controls-smoke.mjs   # ControlPanel + TransportBar: draft seed, deal, random, transport (14)
```

Every suite exits non-zero on failure and prints `… OK` on success.
Run all four after any frontend change; they take ~15s each.
