-- | The shared data vocabulary of the frontend: the `Game` bundle and its
-- | pure accessors, plus the tab enum. The design principle: `snapshots`
-- | holds the watcher's knowledge at every position, computed once per
-- | game by `knowledgeTimeline`; every render merely indexes it, so
-- | scrubbing anywhere on the timeline is O(1).
-- |
-- | Component state and actions live with their components (App and the
-- | Component.* modules) — this module stays pure data so every pane and
-- | child can import it without cycles.
module Kibitzer.Frontend.Types
  ( Game
  , Tab(..)
  , currentKnowledge
  , currentEvent
  , maxPosition
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Maybe (Maybe, fromMaybe)
import Kibitzer.Board (Position)
import Kibitzer.Cascade (CascadeEdge, CascadeFrame)
import Kibitzer.Event (Event)
import Kibitzer.Game (Result)
import Kibitzer.Knowledge (FactId, Knowledge, emptyKnowledge)
import Kibitzer.Player (PlayerId, defaultPlayerCount)

type Game =
  { seedInt :: Int
  , movement :: Boolean -- with seed and player count, the full deal identity
  , result :: Result
  , snapshots :: Array Knowledge
  , positions :: Array (Map PlayerId Position) -- index-aligned with snapshots
  , cascades :: Array CascadeFrame -- also index-aligned; the watcher's derivation frames
  , depths :: Map FactId Int -- frame-local derivation depth of every fact
  , allEdges :: Array CascadeEdge -- the complete premise DAG of the finished game
  }

data Tab = PlayTab | CascadeTab | AboutTab | CodeTab

derive instance Eq Tab

currentKnowledge :: Game -> Int -> Knowledge
currentKnowledge game position =
  fromMaybe (emptyKnowledge defaultPlayerCount) (Array.index game.snapshots position)

-- | The event the timeline cursor sits just after; Nothing at the start.
currentEvent :: Game -> Int -> Maybe Event
currentEvent game position = Array.index game.result.log (position - 1)

maxPosition :: Game -> Int
maxPosition game = Array.length game.result.log
