-- | The About page: what this is, the demo walkthrough in prose, the two
-- | libraries compared, and where they come from. Static prose, set as an
-- | editorial spread in the opening-title sequence's key (cream ground,
-- | condensed display type, the six suspect pieces as marginalia). The
-- | numbers are the measured values from `spago run -p kibitzer-example --
-- | stats` (1,000 seeds/config) and the locked demo seed 768896.
module Kibitzer.Frontend.View.About (aboutPage) where

import Prelude

import Data.Array as Array
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

aboutPage :: forall w a. HH.HTML w a
aboutPage =
  HH.main [ HP.classes (map HH.ClassName [ "prose", "about" ]) ]
    [ masthead
    , section "scarlett" "The idea"
        [ para
            """In Cluedo — Clue, in the States — three cards sit unseen in an
envelope: the murderer, the weapon, the room. Players learn what they
aren't by asking. A suggestion is made, and each player in turn either
passes (they hold none of the three named cards) or privately shows the
suggester one card. Eventually someone names all three envelope cards
and wins."""
        , para
            """This site adds a chair at the table: a kibitzer — the traditional
word for someone who watches a card game over the players' shoulders.
Our kibitzer is worse off than the classic one. It never sees a single
card. Not a hand, not a shown card, nothing. All it gets is the
metadata — who asked what, who passed, who showed something to whom."""
        , pull "Content privacy is not metadata privacy."
        , para
            """And that turns out to be a lot. Three players pass on one
suggestion: nine facts (each holds none of those three). Someone shows a
card and the watcher can't see it — but knows the shower holds at least
one of three named cards, and many turns later, when two of those
candidates have been ruled out elsewhere, that old observation quietly
resolves into a certainty. The headline counter tells the story: cards
seen, zero; facts inferred, dozens."""
        , para
            """If a bystander can reconstruct most of a private card game from
who-asked-whom, the same holds for your phone records, your DNS queries,
and your encrypted messenger's delivery receipts. Content privacy is not
metadata privacy. That is the whole point of this toy — and the little
libraries that do the deducing, generically, are the real subject."""
        ]
    , section "mustard" "What the demo shows"
        [ para
            """The three numbered pages replay one game — seed 768896, six
players — three ways. Every game is a pure function of its seed, so the
URL reproduces the exact deal, dice, and deductions; and the pages are
paced by a discovery stepper that skips the routine passes and lands on
each genuine deduction."""
        , para
            """① Game is the table as it happened, and the watcher's mind beside
it. On the left, ground truth — the actual hands and the envelope — which
the watcher cannot see, there only so you can check with your own eyes
that the notebook never lies. On the right, that notebook: a
detective's-grid of who-holds-what, filling in derivation order, every
new fact wired to the premises it stood on. Step to the finish and watch
the clock: on this seed the watcher pins all three envelope cards —
Peacock, the Knife, the Lounge — one event before a player stands up and
wins with them. The onlooker who never touched a card got there first, by
a single turn."""
        , pull "The onlooker who never touched a card got there first — by a single turn."
        , para
            """② Baskerville is the same game from the watcher's point of view,
with the possibilities in orbit. Early on, player D shows player A a
card; the watcher can't see it, so the three candidates — Mrs. White, the
Wrench, the Billiard Room — lift into an orbit around D, an unresolved
disjunction. There it sits for fifty-odd moves, until the rest of the
table quietly closes every other door: one candidate turns up in another
hand, another is shown to belong to nobody. One press of the stepper
jumps to the very next event, E61, where the circles collapse onto D and
the callout crystallises the new fact — the card D showed, all those
turns ago, was Mrs. White — and, for free, that Mrs. White was never in
the envelope."""
        , para
            """③ Mycroft is the same collapse seen whole. At the deal there are
forty-four trillion legal ways the cards could lie — 44,460,928,512,000
of them, exactly — far too many to draw, so the picture starts on log
paper and estimates the space shrinking. The moment the survivors are few
enough to fit on a screen, the solver enumerates every one of them — the
totality, not a sample — and each pass and show you saw collapses it
further, down the decades, to a single world. A marker falls out for
free: the instant every surviving world agrees on the envelope. On this
game it lands on the same event the notebook does, E102 — the forward
rules leave nothing on the table here."""
        ]
    , section "green" "How often the silent watcher wins"
        [ para
            """Not always — and it scales with the table. Across a thousand
seeded games per configuration (the watcher seeing zero cards throughout),
the rate at which it pins all three envelope cards climbs steeply with
the number of players:"""
        , statsTable
        , para
            """More players means more suggestions, more passes, more shows — more
hidden information bleeding into the open. From three players to six the
solve rate jumps roughly eightfold. And whenever the watcher solves at
all, it always gets there before the winning accusation: the accusation
never teaches it the answer; it had it, or it didn't."""
        , pullEye
        , para
            """The point isn't that the watcher beats the players. At a real table
people get up and walk to the rooms they name, which narrows the leak —
turn on that movement constraint and the six-player rate drops from about
24% to 18%, and a player usually wins first. The point is that it extracts
any certainty at all from pure metadata, and that the more the table
talks, the more it learns. Even when it falls short of a full solve, it is
guessing well: at six players it has pinned, on average, 1.8 of the 3
envelope cards by the end."""
        ]
    , section "peacock" "Two libraries, two temperaments"
        [ para
            """Nothing in the watcher knows the word "Cluedo." It never learned
the rules of the game — it learned how to hold a reason. Underneath are
two small PureScript libraries that answer the same questions in
completely different tempers."""
        , para
            """Baskerville does the legwork. Most engines record what they
believe; Baskerville records every fact paired with the reason it holds —
facts as proof terms, wired into a hash-consed derivation graph — and
grinds one rule set forward, monotonically, until nothing new can be
learned. Because every fact carries its justification, you can point at
any conclusion and ask it why, and get the chain it stood on, all the way
down to what was actually observed. In the truth-maintenance tradition
that chain was bookkeeping, kept for cleanup. Baskerville promotes it to
the product: the explanation is the deliverable. Cluedo is one client in
three rules and a page of code; a meeting scheduler, Sudoku, and a build
graph are others — the surviving meeting slot arrives carrying the reason
every other slot died."""
        , para
            """Mycroft does no legwork — named, like Sherlock's cleverer,
sedentary brother, for pronouncing on facts others bring him. You hand
the whole problem to the Z3 theorem prover and ask a single question: is
there any world consistent with everything seen? It reasons over the
entire model space at once. Where Baskerville walks forward one fact at a
time and can, in principle, fail to reach something that was nonetheless
inevitable, the solver is complete by construction — if a card's place is
forced, no consistent world disagrees."""
        , pull "One proves why, in human terms; the other certifies that."
        , para
            """So the two are complements, not rivals. Baskerville is incremental,
explanatory, and fast on a growing log — the right tool when you want the
worked reason and you want it to update as observations arrive. Mycroft is
whole-space and decisive — the right tool when you want a guaranteed
verdict, or a witness world, or an answer to "is this even possible?"
The third package, baskerville-mycroft, sits the solver behind
Baskerville's own seam and uses it as a measuring instrument for the
rules themselves: is the engine sound — does it ever derive a fact that
isn't truly forced? Where is the completeness gap — facts that were
logically inevitable that the forward rules never reached? Z3's unsat
core — the minimal set of observations that force a conclusion — is the
exact mirror of Baskerville's "which facts did this stand on." One proves
why, in human terms; the other certifies that, and keeps the first
honest. It runs against a native Z3, or entirely in the browser, compiled
to WebAssembly."""
        ]
    , section "plum" "Antecedents"
        [ para
            """None of this is new — except the visualisations here, which are my
own original work. The core move belongs to the truth-maintenance
systems of the eighties — Doyle's JTMS (1979), de Kleer's ATMS (1986):
don't record beliefs, record beliefs paired with the reason you hold
them. Baskerville keeps that entirely, and deliberately declines the other
half — the labels that flip IN and OUT as evidence is revised. Here
monotonicity is the feature: a watcher is a fold over observations, the
same log gives the same feed, and belief revision, when you want it, is
just replaying the fold without the retracted fact."""
        , para
            """The TMS itself didn't survive as a thing; it was taken apart and its
organs transplanted into lineages that did each job better. The
dependency-directed backtracking became conflict-driven clause learning,
and now runs inside every SAT and SMT solver — Z3 included, so Mycroft is
literally powered by the TMS's own third pillar. The IN/OUT labelling was
reconstructed as the stable-model semantics of logic programs and lives on
in Answer Set Programming. The ATMS's assumption labels found their mature
algebraic form as provenance semirings in database theory. Every successor
absorbed the machinery and buried the explanations as plumbing — CDCL
burns its nogoods as fuel, view maintenance keeps the view and discards
the why."""
        , para
            """The written-up reason — the derivation graph as the thing you
actually ship, renderable and queryable and testable — is the piece still
lying on the table. That is what Baskerville picks up."""
        ]
    , section "white" "Honesty"
        [ para
            """The engine is sound and very nearly complete. Its soundness — the
notebook never lies, from any seat, at any moment — is enforced by
property tests over thousands of random games, and independently by Z3.
For completeness we had Z3 play the perfect watcher over the same games;
Baskerville's forward rules derive 96–99% of everything logically
certain, and on the demo seed they reach the full solution at the very
same event the solver does. Simplifications are documented in the code
and the README: no secret passages, committed journeys, and the stock
players suggest at random rather than strategically."""
        , para
            """Written in PureScript — a pure Halogen app over a pure game core,
the world-space view enumerated by Z3. MIT licensed."""
        ]
    , colophon
    ]

-- | The feature masthead: eyebrow, condensed title with the red full-stop,
-- | a deck, and the six suspect pieces as a cast band.
masthead :: forall w a. HH.HTML w a
masthead =
  HH.header [ HP.class_ (HH.ClassName "about-masthead") ]
    [ HH.div [ HP.class_ (HH.ClassName "sec-inner") ]
        [ HH.p [ HP.class_ (HH.ClassName "eyebrow") ] [ HH.text "A deduction from metadata" ]
        , HH.h1 [ HP.class_ (HH.ClassName "feature-title") ]
            [ HH.text "The silent watcher"
            , HH.span [ HP.class_ (HH.ClassName "stop") ] [ HH.text "." ]
            ]
        , HH.p [ HP.class_ (HH.ClassName "feature-deck") ]
            [ HH.text "An onlooker at a game of Cluedo who never sees a single card, deducing the murder from the public metadata alone — and the two small PureScript libraries that do the deducing." ]
        , castBand
        ]
    ]

castBand :: forall w a. HH.HTML w a
castBand =
  HH.div [ HP.class_ (HH.ClassName "cast") ] (map member suspects)
  where
  member s =
    HH.figure [ HP.class_ (HH.ClassName "cast-piece") ]
      [ pawnImg s.file
      , HH.figcaption_ [ HH.text s.name ]
      ]
  suspects =
    [ { name: "Scarlett", file: "scarlett" }
    , { name: "Mustard", file: "mustard" }
    , { name: "White", file: "white" }
    , { name: "Green", file: "green" }
    , { name: "Peacock", file: "peacock" }
    , { name: "Plum", file: "plum" }
    ]

-- | A titled section, marked in the margin by a suspect piece.
section :: forall w a. String -> String -> Array (HH.HTML w a) -> HH.HTML w a
section pawn title body =
  HH.section [ HP.class_ (HH.ClassName "prose-section") ]
    [ HH.div [ HP.class_ (HH.ClassName "sec-inner") ]
        (Array.cons (sectionHead pawn title) body)
    ]

sectionHead :: forall w a. String -> String -> HH.HTML w a
sectionHead pawn title =
  HH.div [ HP.class_ (HH.ClassName "sec-head") ]
    [ pawnImg pawn
    , HH.h2_ [ HH.text title ]
    ]

pawnImg :: forall w a. String -> HH.HTML w a
pawnImg file =
  HH.img
    [ HP.class_ (HH.ClassName "sec-piece")
    , HP.src ("pieces/pawn-" <> file <> ".svg")
    , HP.alt ""
    ]

para :: forall w a. String -> HH.HTML w a
para text = HH.p_ [ HH.text text ]

-- | A pulled quote, floated as a magazine call-out.
pull :: forall w a. String -> HH.HTML w a
pull text = HH.blockquote [ HP.class_ (HH.ClassName "pull") ] [ HH.text text ]

-- | The watcher's eye, floated big into the margin as a graphic call-out.
pullEye :: forall w a. HH.HTML w a
pullEye =
  HH.figure [ HP.classes (map HH.ClassName [ "pull", "pull-eye" ]) ]
    [ HH.img [ HP.src "eye.svg", HP.alt "the watcher" ] ]

-- | The end-card: the four registry packages on ink ground, the eye as
-- | the watcher's signature.
colophon :: forall w a. HH.HTML w a
colophon =
  HH.section [ HP.classes (map HH.ClassName [ "prose-section", "colophon" ]) ]
    [ HH.div [ HP.class_ (HH.ClassName "sec-inner") ]
        [ HH.div [ HP.class_ (HH.ClassName "sec-head") ]
            [ HH.img [ HP.class_ (HH.ClassName "sec-piece"), HP.src "eye.svg", HP.alt "" ]
            , HH.h2_ [ HH.text "The libraries" ]
            ]
        , para "Published to the PureScript registry, in four small pieces:"
        , packageList
        ]
    ]

-- | External link, opened in a new tab.
plink :: forall w a. String -> String -> HH.HTML w a
plink href text =
  HH.a
    [ HP.href href, HP.target "_blank", HP.rel "noopener noreferrer" ]
    [ HH.text text ]

statsTable :: forall w a. HH.HTML w a
statsTable =
  HH.table [ HP.class_ (HH.ClassName "stats-table") ]
    [ HH.thead_
        [ HH.tr_ (map th [ "players", "fully solved", "facts inferred", "envelope cards pinned" ]) ]
    , HH.tbody_ (map row rows)
    ]
  where
  th s = HH.th_ [ HH.text s ]

  row r = HH.tr_
    [ HH.td_ [ HH.text r.players ]
    , HH.td [ HP.class_ (HH.ClassName "stat-solved") ] [ HH.text r.solved ]
    , HH.td_ [ HH.text r.facts ]
    , HH.td_ [ HH.text r.env ]
    ]

  -- board-off, 1,000 seeds/config; solved% == beat% in every cell
  rows =
    [ { players: "3", solved: "3.1%", facts: "51.1", env: "1.0 / 3" }
    , { players: "4", solved: "8.7%", facts: "75.9", env: "1.3 / 3" }
    , { players: "5", solved: "15.1%", facts: "100.8", env: "1.6 / 3" }
    , { players: "6", solved: "23.5%", facts: "124.0", env: "1.8 / 3" }
    ]

packageList :: forall w a. HH.HTML w a
packageList =
  HH.ul [ HP.class_ (HH.ClassName "package-list") ] (map item pkgs)
  where
  item p = HH.li_
    [ plink p.href p.name
    , HH.text (" — " <> p.blurb)
    ]

  pkgs =
    [ { name: "baskerville-core"
      , href: "https://pursuit.purescript.org/packages/purescript-baskerville-core"
      , blurb: "the forward-deriving kernel: facts as proof terms, the hash-consed derivation DAG, and the why-query over it."
      }
    , { name: "mycroft"
      , href: "https://pursuit.purescript.org/packages/purescript-mycroft"
      , blurb: "the SMT bridge: encode observations for Z3 and read back a model or an unsat core."
      }
    , { name: "baskerville-mycroft"
      , href: "https://pursuit.purescript.org/packages/purescript-baskerville-mycroft"
      , blurb: "the oracle seam — Z3 behind the engine, measuring soundness and the completeness gap."
      }
    , { name: "mycroft-z3-wasm"
      , href: "https://pursuit.purescript.org/packages/purescript-mycroft-z3-wasm"
      , blurb: "Z3 compiled to WebAssembly, so the solver runs entirely in the browser."
      }
    ]
