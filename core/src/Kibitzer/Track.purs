-- | Positions replayed from the log. Lives apart from `Kibitzer.Board`
-- | (geometry, no events) and `Kibitzer.Event` (which embeds `Position`)
-- | so neither needs the other's whole world. The same fold serves the
-- | legality tests and the frontend's map — what is tested is exactly
-- | what is rendered.
module Kibitzer.Track
  ( positionsAfter
  , positionsTimeline
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (fromMaybe)
import Kibitzer.Board (Position, startPositions)
import Kibitzer.Event (Event(..), Log)
import Kibitzer.Player (PlayerCount, PlayerId)

positionsAfter :: PlayerCount -> Log -> Map PlayerId Position
positionsAfter count log =
  fromMaybe (startPositions count) (Array.last (positionsTimeline count log))

-- | One entry per timeline position, 0 (before anything) through
-- | `length log`, index-aligned with `Infer.knowledgeTimeline`.
positionsTimeline :: PlayerCount -> Log -> Array (Map PlayerId Position)
positionsTimeline count log =
  Array.cons start (Array.scanl step start log)
  where
  start = startPositions count

  step positions = case _ of
    Moved { player, position } -> Map.insert player position positions
    _ -> positions
