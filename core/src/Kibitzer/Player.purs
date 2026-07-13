-- | Seats at the table. Players are identified by seat index, clockwise;
-- | the refutation query order and the round-robin hand sizes both fall
-- | out of that ordering.
module Kibitzer.Player
  ( PlayerId(..)
  , PlayerCount
  , mkPlayerCount
  , playerCountToInt
  , allPlayers
  , nextPlayer
  , queriedAfter
  , totalDealt
  , handSizes
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (allCards, allCategories)

newtype PlayerId = PlayerId Int

derive instance Eq PlayerId
derive instance Ord PlayerId

instance Show PlayerId where
  show (PlayerId i) = "(PlayerId " <> show i <> ")"

-- | Between three and six seats; enforced by the smart constructor.
newtype PlayerCount = PlayerCount Int

derive instance Eq PlayerCount

instance Show PlayerCount where
  show (PlayerCount n) = "(PlayerCount " <> show n <> ")"

mkPlayerCount :: Int -> Maybe PlayerCount
mkPlayerCount n
  | n >= 3 && n <= 6 = Just (PlayerCount n)
  | otherwise = Nothing

playerCountToInt :: PlayerCount -> Int
playerCountToInt (PlayerCount n) = n

allPlayers :: PlayerCount -> Array PlayerId
allPlayers (PlayerCount n) = map PlayerId (Array.range 0 (n - 1))

nextPlayer :: PlayerCount -> PlayerId -> PlayerId
nextPlayer (PlayerCount n) (PlayerId i) = PlayerId ((i + 1) `mod` n)

-- | The players queried to refute a suggestion, clockwise from the
-- | suggester's left, excluding the suggester.
queriedAfter :: PlayerCount -> PlayerId -> Array PlayerId
queriedAfter (PlayerCount n) (PlayerId i) =
  map (\k -> PlayerId ((i + k) `mod` n)) (Array.range 1 (n - 1))

-- | Cards dealt to players: the deck minus one envelope card per category.
totalDealt :: Int
totalDealt = Array.length allCards - Array.length allCategories

-- | Round-robin deal starting at seat 0: with four players the 18 cards
-- | split 5,5,4,4. Uneven hands are load-bearing for inference — knowing
-- | a hand is *full* excludes every other card from it.
handSizes :: PlayerCount -> Map PlayerId Int
handSizes count =
  let
    n = playerCountToInt count
    base = totalDealt / n
    extras = totalDealt `mod` n
    sizeOf (PlayerId i) = base + if i < extras then 1 else 0
  in
    Map.fromFoldable (map (\p -> Tuple p (sizeOf p)) (allPlayers count))
