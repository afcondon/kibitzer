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
  , Discovery
  , discoveries
  , isDeductive
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
import Kibitzer.Knowledge (FactId, Knowledge, Rule(..), emptyKnowledge)
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

data Tab = PlayTab | BaskervilleTab | MycroftTab

derive instance Eq Tab

-- | A deductive moment on the timeline: a fact the watcher *worked out*
-- | (not merely observed), at the position where it first appears. The
-- | discovery stepper walks this list — "step to the next thing figured
-- | out" — as distinct from the event stepper's "next thing that happened".
type Discovery = { position :: Int, factId :: FactId, rule :: Rule }

-- | Every deductive fact in timeline order, read straight off the
-- | per-position `newFacts` the cascade already computed. Direct
-- | observations (own hand, a shown card, a pass) are skipped — they are
-- | what the watcher is *told*, not what it *derives*.
discoveries :: Game -> Array Discovery
discoveries game =
  Array.concat (Array.mapWithIndex frameDiscoveries game.cascades)
  where
  frameDiscoveries position frame =
    frame.newFacts
      # Array.filter (isDeductive <<< _.justification.rule)
      # map (\f -> { position, factId: f.id, rule: f.justification.rule })

-- | Direct facts are told to the watcher; deductive facts are worked out.
-- | The discovery stepper lands only on the latter.
isDeductive :: Rule -> Boolean
isDeductive = case _ of
  OwnHand -> false
  SawCard -> false
  PassImpliesLacks -> false
  _ -> true

currentKnowledge :: Game -> Int -> Knowledge
currentKnowledge game position =
  fromMaybe (emptyKnowledge defaultPlayerCount) (Array.index game.snapshots position)

-- | The event the timeline cursor sits just after; Nothing at the start.
currentEvent :: Game -> Int -> Maybe Event
currentEvent game position = Array.index game.result.log (position - 1)

maxPosition :: Game -> Int
maxPosition game = Array.length game.result.log
