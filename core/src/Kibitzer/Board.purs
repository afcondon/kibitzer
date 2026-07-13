-- | The board, abstracted to what matters for the information game: rooms
-- | at fixed coordinates in a stylised 3×3 layout (corners matching the
-- | classic board), corridor travel as a step distance between rooms, and
-- | two dice. A player's position is either resting in a room or committed
-- | to a journey.
-- |
-- | `InRoom r` means *resting in r having already suggested there (or
-- | having started the game there)* — on your next turn you must pick a
-- | destination and roll. That single reading makes the departure
-- | obligation structural: no flags, no special first turn, and nobody
-- | ever suggests without an immediately preceding arrival.
-- |
-- | Simplifications, stated plainly: no secret passages; no mid-journey
-- | retargeting (journeys are committed — a mid-journey epiphany is
-- | covered by accusing from anywhere); no dragging the suggested
-- | suspect's token (seats are deliberately not identified with suspect
-- | cards); overshoot is absorbed (you may stop on entering a room).
module Kibitzer.Board
  ( Position(..)
  , roomCoords
  , distance
  , startPositions
  , rollTwoDice
  ) where

import Prelude

import Data.Array as Array
import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Map as Map
import Data.Ord (abs)
import Data.Show.Generic (genericShow)
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Room(..))
import Kibitzer.Player (PlayerCount, PlayerId, allPlayers)
import Kibitzer.Rng (Seed, uniform)

data Position
  = InRoom Room
  | EnRoute { from :: Room, to :: Room, remaining :: Int }

derive instance Eq Position
derive instance Ord Position
derive instance Generic Position _

instance Show Position where
  show = genericShow

-- | The 3×3 layout, corners as on the classic board: Kitchen top-left,
-- | Conservatory top-right, Lounge bottom-left, Study bottom-right.
roomCoords :: Room -> { x :: Int, y :: Int }
roomCoords = case _ of
  Kitchen -> { x: 0, y: 0 }
  Ballroom -> { x: 1, y: 0 }
  Conservatory -> { x: 2, y: 0 }
  DiningRoom -> { x: 0, y: 1 }
  BilliardRoom -> { x: 1, y: 1 }
  Library -> { x: 2, y: 1 }
  Lounge -> { x: 0, y: 2 }
  Hall -> { x: 1, y: 2 }
  Study -> { x: 2, y: 2 }

-- | Corridor steps between rooms: 3·manhattan + 2, so adjacent rooms are
-- | 5 steps and the far corner 14. Against two dice (mean 7), an adjacent
-- | room is usually one roll away and the far corner about two.
distance :: Room -> Room -> Int
distance r1 r2
  | r1 == r2 = 0
  | otherwise =
      let
        a = roomCoords r1
        b = roomCoords r2
      in
        3 * (abs (a.x - b.x) + abs (a.y - b.y)) + 2

-- | Fixed, seed-free starting rooms (corners first, then edge rooms), so
-- | the deal and the whole classic game consume exactly the same seed
-- | stream whether or not movement is enabled.
startPositions :: PlayerCount -> Map PlayerId Position
startPositions count =
  Map.fromFoldable
    ( Array.zipWith (\p room -> Tuple p (InRoom room))
        (allPlayers count)
        [ Kitchen, Study, Conservatory, Lounge, Ballroom, Hall ]
    )

rollTwoDice :: Seed -> Tuple Int Seed
rollTwoDice seed0 =
  let
    Tuple d1 seed1 = uniform 6 seed0
    Tuple d2 seed2 = uniform 6 seed1
  in
    Tuple (d1 + d2 + 2) seed2
