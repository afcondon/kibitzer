-- | Set up a game: pick the envelope (one card per category, guaranteed
-- | by the Solution type), shuffle the remaining 18 cards, and deal them
-- | round-robin from seat 0.
module Kibitzer.Deal
  ( Setup
  , deal
  ) where

import Prelude

import Data.Array as Array
import Data.FoldableWithIndex (foldlWithIndex)
import Data.Map (Map)
import Data.Map as Map
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card, allCards, nonEmptyRooms, nonEmptySuspects, nonEmptyWeapons)
import Kibitzer.Player (PlayerCount, PlayerId(..), allPlayers, playerCountToInt)
import Kibitzer.Rng (Seed, pick, shuffle)
import Kibitzer.Suggestion (Solution, suggestionCards)

type Setup = { solution :: Solution, hands :: Map PlayerId (Set Card) }

deal :: PlayerCount -> Seed -> Tuple Setup Seed
deal count seed0 =
  let
    Tuple suspect s1 = pick nonEmptySuspects seed0
    Tuple weapon s2 = pick nonEmptyWeapons s1
    Tuple room s3 = pick nonEmptyRooms s2
    solution = { suspect, weapon, room }
    envelope = suggestionCards solution
    remaining = Array.filter (\c -> not (Set.member c envelope)) allCards
    Tuple shuffled s4 = shuffle remaining s3
  in
    Tuple { solution, hands: dealRoundRobin count shuffled } s4

dealRoundRobin :: PlayerCount -> Array Card -> Map PlayerId (Set Card)
dealRoundRobin count cards =
  let
    n = playerCountToInt count
    emptyHands = Map.fromFoldable (map (\p -> Tuple p Set.empty) (allPlayers count))
    give i hands card = Map.insertWith Set.union (PlayerId (i `mod` n)) (Set.singleton card) hands
  in
    foldlWithIndex give emptyHands cards
