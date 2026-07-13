-- | The About tab: what this is, why metadata is the subject, and what
-- | the experiments found. Static prose; the numbers come from
-- | `spago run -p kibitzer-example -- stats 100`.
module Kibitzer.Frontend.View.About (aboutPage) where

import Prelude

import Data.Array as Array
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

aboutPage :: forall w a. HH.HTML w a
aboutPage =
  HH.main [ HP.class_ (HH.ClassName "prose") ]
    [ section "The idea"
        [ para
            """In Cluedo, three cards sit unseen in an envelope: the murderer, the
weapon, the room. Players learn what they aren't by asking questions —
a suggestion is made, and players in turn either pass (they hold none
of the three named cards) or privately show the suggester one card."""
        , para
            """This site adds a fifth chair at the table: a kibitzer — the
traditional word for someone who watches a card game over the players'
shoulders. Our kibitzer is worse off than the classic one: they never
see a single card. Not a hand, not a shown card, nothing. All they get
is the metadata — who asked what, who passed, who showed something."""
        , para
            """And that turns out to be a lot. Three players pass on one
suggestion: nine facts. Someone shows a card: the watcher can't see it,
but knows the shower holds at least one of three named cards — and many
turns later, when two of those candidates have been ruled out elsewhere,
that old observation quietly resolves into a certainty. The headline
counter tells the story: cards seen, zero; facts inferred, dozens."""
        , para
            """If a bystander can reconstruct most of a private card game from
who-asked-whom, the same holds for your phone records, your DNS
queries, and your encrypted messenger's delivery receipts. Content
privacy is not metadata privacy. That is the whole point of this toy."""
        ]
    , section "What you're looking at"
        [ para
            """The left pane is ground truth — the actual hands, the envelope,
each card as it is shown. The watcher cannot see any of it; it's there
so you can verify with your own eyes that the notebook on the right
never lies. The right pane is the watcher's mind: the detective-notepad
grid (✓ certainly holds, ✗ certainly doesn't, thin red outlines for
live "showed one of these" disjunctions) and, below it, the derivation
feed — every fact with the rule and the event that produced it. Scrub
the timeline; facts only ever accumulate."""
        , para
            """Every game is a pure function of its seed, so the URL reproduces
the exact game — deal, dice, deductions and all."""
        ]
    , section "The board variant"
        [ para
            """Real Cluedo makes you be in the room you name: you roll dice and
walk there first. The Board toggle restores that constraint over a
stylised nine-room map — a room is a departure obligation, journeys are
committed, and arriving triggers a suggestion in that room the same
turn. The watcher sees every roll and every token, and its inference
engine deliberately learns nothing from them: a token's path is a
hunch, and the notebook holds no hunches."""
        , para
            """We expected the board to help the watcher. It mostly doesn't —
which is more interesting. A hundred seeded games per configuration:"""
        , statsTable
        , para
            """Two findings. Table size is the watcher's real ally: at six
players the watcher fully names all three envelope cards in 31% of
classic games (versus 2% at three players) — every suggestion sweeps
more hands, and six three-card hands fill up fast. And the board mostly
protects the players: at five and six players movement roughly halves
the watcher's solve rate. Suggestions get scarcer per turn, and the
room slot stops being a free choice — players suggest whatever room
they could reach, the same nearby rooms recur, and each pass repeats
things the watcher already knew. Metadata inference thrives on varied
questions; the board forces repetitive ones."""
        ]
    , section "Honesty"
        [ para
            """The inference engine is sound but deliberately not complete: it
propagates certainties and never guesses, so a cleverer watcher (or a
SAT solver) could squeeze out a little more. Simplifications are
documented in the code and the README: no secret passages, no dragging
the named suspect's token, committed journeys, and the stock players
suggest at random rather than strategically. The soundness claim — the
notebook never lies, from any seat, at any moment — is enforced by
property tests over thousands of random games."""
        , para
            """Written in PureScript (a pure Halogen app over a pure game core);
MIT licensed."""
        ]
    ]

section :: forall w a. String -> Array (HH.HTML w a) -> HH.HTML w a
section title body =
  HH.section [ HP.class_ (HH.ClassName "prose-section") ]
    (Array.cons (HH.h2_ [ HH.text title ]) body)

para :: forall w a. String -> HH.HTML w a
para text = HH.p_ [ HH.text text ]

statsTable :: forall w a. HH.HTML w a
statsTable =
  HH.table [ HP.class_ (HH.ClassName "stats-table") ]
    [ HH.thead_
        [ HH.tr_ (map th [ "players", "board", "suggestions/game", "watcher facts", "fully solved" ]) ]
    , HH.tbody_ (map row rows)
    ]
  where
  th s = HH.th_ [ HH.text s ]

  row r = HH.tr_
    [ HH.td_ [ HH.text r.players ]
    , HH.td_ [ HH.text r.board ]
    , HH.td_ [ HH.text r.suggs ]
    , HH.td_ [ HH.text r.facts ]
    , HH.td [ HP.class_ (HH.ClassName "stat-solved") ] [ HH.text r.solved ]
    ]

  rows =
    [ { players: "3", board: "off", suggs: "34.4", facts: "54.0", solved: "2%" }
    , { players: "3", board: "on", suggs: "24.3", facts: "43.0", solved: "6%" }
    , { players: "4", board: "off", suggs: "32.2", facts: "74.2", solved: "6%" }
    , { players: "4", board: "on", suggs: "25.0", facts: "65.3", solved: "10%" }
    , { players: "5", board: "off", suggs: "33.1", facts: "98.7", solved: "14%" }
    , { players: "5", board: "on", suggs: "26.4", facts: "85.6", solved: "7%" }
    , { players: "6", board: "off", suggs: "33.4", facts: "121.7", solved: "31%" }
    , { players: "6", board: "on", suggs: "26.9", facts: "108.7", solved: "12%" }
    ]
