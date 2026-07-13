-- | A suggestion names one card from each category. The hidden solution
-- | has exactly the same shape — the type itself guarantees the envelope
-- | holds one suspect, one weapon, and one room.
module Kibitzer.Suggestion
  ( Suggestion
  , Solution
  , suggestionCards
  , matches
  ) where

import Prelude

import Data.Set (Set)
import Data.Set as Set
import Kibitzer.Cards (Card(..), Suspect, Weapon, Room)

type Suggestion = { suspect :: Suspect, weapon :: Weapon, room :: Room }

type Solution = Suggestion

suggestionCards :: Suggestion -> Set Card
suggestionCards { suspect, weapon, room } =
  Set.fromFoldable [ SuspectCard suspect, WeaponCard weapon, RoomCard room ]

-- | The cards of a hand that could refute a suggestion.
matches :: Suggestion -> Set Card -> Set Card
matches suggestion hand = Set.intersection (suggestionCards suggestion) hand
