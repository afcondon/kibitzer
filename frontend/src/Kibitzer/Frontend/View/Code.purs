-- | The Code tab: the parts of the design worth showing off, as real
-- | excerpts from the core with short commentary. The excerpts are
-- | duplicated here as string literals on purpose — this page is an
-- | exhibition, not a build artifact, and the golden tests keep the
-- | originals honest.
module Kibitzer.Frontend.View.Code (codePage) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

codePage :: forall w a. HH.HTML w a
codePage =
  HH.main [ HP.class_ (HH.ClassName "prose") ]
    [ intro
    , exhibit "The privacy model is one function"
        """observe :: Perspective -> Event -> Observation
observe perspective = case _ of
  ...
  CardShown { by, to, card, suggestion } ->
    ObsShowed
      { by, to, suggestion
      , card: case perspective of
          Watcher -> Nothing
          PlayerView p -> if p == by || p == to then Just card
                          else Nothing
      }"""
        [ para
            """The simulator produces one ground-truth event log. Everything any
mind is allowed to know is a projection of it, and the entire privacy
model — who may see a shown card — is this one function. The watcher
gets `card: Nothing`; the shower and the receiver get `Just card`;
everyone gets the metadata. There is nowhere else a leak could hide."""
        ]
    , exhibit "A player is a watcher with better seats"
        """learn :: Tuple EventId Observation -> Knowledge -> Knowledge

knowledgeAt :: PlayerCount -> Perspective -> Int -> Log -> Knowledge
knowledgeAt count perspective n log =
  foldl (flip learn) (emptyKnowledge count)
    (Array.take n (observeLog perspective log))"""
        [ para
            """A mind is a fold. The watcher folds `learn` over the public
projection; a player folds the same function over the same log seen
from a better seat. One inference engine serves everyone — including
the simulated players themselves, who accuse exactly when their own
fold determines the envelope. The difference between "player" and
"eavesdropper" is nothing but which events were witnessed."""
        , para
            """Time travel comes free: rendering the game at position n is
folding the first n observations, so the timeline scrubber just indexes
an array of precomputed snapshots."""
        ]
    , exhibit "Facts carry their reasons"
        """data Claim
  = Holds PlayerId Card
  | Lacks PlayerId Card
  | InEnvelope Card
  | NotInEnvelope Card

type Justification =
  { rule :: Rule                -- which deduction fired
  , source :: EventId           -- the event whose processing derived it
  , origins :: Array EventId    -- show-events the derivation drew on
  , premises :: Array FactId    -- prior facts it consumed
  }

type Fact = { id :: FactId, claim :: Claim, justification :: Justification }"""
        [ para
            """Every fact the watcher ever writes down carries its provenance.
That is what turns the notebook from a magic grid into an explainable
one — the feed can say "E61 · only candidate left — B holds the
Billiard Room (resolving the card shown at E2)" because the data does.
The premises make derivation a DAG — acyclic for free, since a fact can
only cite facts with smaller ids — and that DAG is exactly what the
Cascade tab draws."""
        ]
    , exhibit "Deduction is a fixpoint of monotone rules"
        """saturate :: EventId -> Knowledge -> Knowledge
saturate source knowledge =
  let next = saturateOnce source knowledge
  in if next == knowledge then knowledge else saturate source next

ruleEnvelopeByElimination :: Knowledge -> Array Derived
ruleEnvelopeByElimination knowledge@(Knowledge k) = do
  c <- allCards
  guard (Array.all (\p -> Set.member c (lacksOf knowledge p))
                   (allPlayers k.playerCount))
  let premises = Array.mapMaybe (\p -> factIdFor (Lacks p c) knowledge)
                                (allPlayers k.playerCount)
  pure { claim: InEnvelope c, rule: EnvelopeByElimination
       , origins: [], premises }"""
        [ para
            """Each deduction rule is a small, individually-tested function from
knowledge to new claims — the Array monad reads like the quantifier it
is: for every card that every player is known to lack, the card is in
the envelope. `saturate` runs the rules to a fixpoint. Termination is
by monotonicity: rules only add claims to finite sets or shrink
disjunction candidates, nothing is ever retracted, so a pass that
changes nothing is the fixpoint — and one must come."""
        ]
    , exhibit "Games are integers"
        """-- Park–Miller via Schrage's algorithm: every intermediate
-- product fits in a 32-bit Int.
step :: Seed -> Tuple Int Seed
step (Seed s) =
  let
    hi = s / schrageQ
    lo = s `mod` schrageQ
    next = multiplier * lo - schrageR * hi
    wrapped = if next <= 0 then next + modulus else next
  in
    Tuple wrapped (Seed wrapped)"""
        [ para
            """No effects anywhere in the core — randomness is a hand-rolled
linear congruential generator threaded through pure functions. A game
is therefore a pure function of one integer, which is why the URL of
this page reproduces a game exactly: deal, dice, refutations,
deductions and all."""
        ]
    , exhibit "The theorems"
        """-- over random seeds, table sizes, and both modes, at EVERY
-- prefix of the log, for EVERY perspective:
quickCheck' 25 \seedInt countInt moves ->
  let gc = runGame seedInt countInt moves
  in Array.all
       (\perspective ->
          Array.all (\k -> sound gc k && consistent k)
                    (timeline gc perspective))
       (perspectives gc)"""
        [ para
            """The claims the demo rests on are property-tested as theorems over
random games: soundness (no perspective ever infers anything false of
the actual hidden deal — the notebook never lies), monotonicity
(knowledge only grows), player ⊇ watcher (public inference is a lower
bound on every player's private knowledge), and fixpoint idempotence.
Golden tests pin two full seed-42 games — classic and board — so any
change to the engine that alters behaviour fails loudly."""
        ]
    ]

intro :: forall w a. HH.HTML w a
intro =
  HH.section [ HP.class_ (HH.ClassName "prose-section") ]
    [ HH.h2_ [ HH.text "Six small exhibits" ]
    , para
        """The engine is deliberately written as an example of functional
programming worth reading: algebraic data types, sets and folds,
provenance-carrying values, no partial functions, and effects only at
the very edges. These are the load-bearing pieces."""
    ]

exhibit :: forall w a. String -> String -> Array (HH.HTML w a) -> HH.HTML w a
exhibit title code commentary =
  HH.section [ HP.class_ (HH.ClassName "prose-section exhibit") ]
    ( [ HH.h2_ [ HH.text title ]
      , HH.pre_ [ HH.code_ [ HH.text code ] ]
      ]
        <> commentary
    )

para :: forall w a. String -> HH.HTML w a
para text = HH.p_ [ HH.text text ]
