-- | How a player plays. Policies consult the player's own `Knowledge` —
-- | built by the same inference engine as the watcher's, just from a
-- | richer observation stream. The engine is dogfooded: a player accuses
-- | exactly when their own fold of `learn` has determined the envelope.
module Kibitzer.Policy
  ( Policy
  , randomLegalPolicy
  , randomSuggestion
  ) where

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Maybe (Maybe)
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card, nonEmptyRooms, nonEmptySuspects, nonEmptyWeapons)
import Kibitzer.Knowledge (Knowledge, solutionIfKnown)
import Kibitzer.Rng (Seed, pick)
import Kibitzer.Suggestion (Solution, Suggestion)

type Policy =
  { suggest :: Knowledge -> Seed -> Tuple Suggestion Seed
  , chooseShown :: Suggestion -> NonEmptyArray Card -> Seed -> Tuple Card Seed
  , accuse :: Knowledge -> Maybe Solution
  }

-- | Suggest uniformly at random (which may probe with cards the player
-- | holds — realistic, and useful noise for the watcher demo), show a
-- | uniformly chosen refuting card, and accuse the moment the player's
-- | own knowledge determines the solution.
randomLegalPolicy :: Policy
randomLegalPolicy =
  { suggest: \_ seed -> randomSuggestion seed
  , chooseShown: \_ refuters seed -> pick refuters seed
  , accuse: solutionIfKnown
  }

randomSuggestion :: Seed -> Tuple Suggestion Seed
randomSuggestion seed0 =
  let
    Tuple suspect seed1 = pick nonEmptySuspects seed0
    Tuple weapon seed2 = pick nonEmptyWeapons seed1
    Tuple room seed3 = pick nonEmptyRooms seed2
  in
    Tuple { suspect, weapon, room } seed3
