-- | Shared game fixtures: the demo and the tests both need a simulated
-- | game plus its ground truth (which only the simulation can see — the
-- | watcher never does).
module Kibitzer.Smt.Fixture
  ( gameFor
  , seed42
  , GameTruth
  , truthOf
  , trueOfDeal
  , actualDeal
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card)
import Kibitzer.Event (Event(..))
import Kibitzer.Game (Result, simulate)
import Kibitzer.Knowledge (Claim(..))
import Kibitzer.Player (PlayerId, defaultPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Smt.Theory (Holder(..))
import Kibitzer.Suggestion (Solution, suggestionCards)

gameFor :: Int -> Result
gameFor seedInt = simulate
  { playerCount: defaultPlayerCount
  , seed: mkSeed seedInt
  , policy: randomLegalPolicy
  , maxTurns: 1200
  , movement: false
  }

-- | The golden game the core test suite pins (WatcherSpec: 51 facts,
-- | four cards placed exactly, envelope not yet solved).
seed42 :: Result
seed42 = gameFor 42

type GameTruth =
  { hands :: Map PlayerId (Set Card)
  , solution :: Solution
  }

truthOf :: Result -> GameTruth
truthOf result =
  { hands: case Array.head result.log of
      Just (GameDealt d) -> d.hands
      _ -> Map.empty
  , solution: result.solution
  }

trueOfDeal :: GameTruth -> Claim -> Boolean
trueOfDeal truth = case _ of
  Holds p c -> Set.member c (handOf p)
  Lacks p c -> not (Set.member c (handOf p))
  InEnvelope c -> Set.member c solutionCards
  NotInEnvelope c -> not (Set.member c solutionCards)
  where
  handOf p = fromMaybe Set.empty (Map.lookup p truth.hands)
  solutionCards = suggestionCards truth.solution

-- | The hidden deal in the same shape `dealFromModel` decodes — for
-- | rendering the real world next to a countermodel.
actualDeal :: GameTruth -> Map Card Holder
actualDeal truth = Map.fromFoldable (handEntries <> envelopeEntries)
  where
  handEntries :: Array (Tuple Card Holder)
  handEntries = Map.toUnfoldable truth.hands >>= \(Tuple p cards) ->
    Set.toUnfoldable cards <#> \c -> Tuple c (Seat p)

  envelopeEntries :: Array (Tuple Card Holder)
  envelopeEntries =
    Set.toUnfoldable (suggestionCards truth.solution) <#> \c -> Tuple c Envelope
