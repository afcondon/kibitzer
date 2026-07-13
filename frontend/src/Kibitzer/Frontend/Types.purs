-- | Shared state and action types for the frontend. The design principle:
-- | `snapshots` holds the watcher's knowledge at every position, computed
-- | once per game by `knowledgeTimeline`; every render merely indexes it,
-- | so scrubbing anywhere on the timeline is O(1).
module Kibitzer.Frontend.Types
  ( Game
  , State
  , Action(..)
  , currentKnowledge
  , currentEvent
  , maxPosition
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Maybe (Maybe, fromMaybe)
import Kibitzer.Board (Position)
import Kibitzer.Event (Event)
import Kibitzer.Game (Result)
import Kibitzer.Knowledge (Knowledge, emptyKnowledge)
import Kibitzer.Player (PlayerId, defaultPlayerCount)

type Game =
  { seedInt :: Int
  , result :: Result
  , snapshots :: Array Knowledge
  , positions :: Array (Map PlayerId Position) -- index-aligned with snapshots
  }

type State =
  { seedInput :: String
  , playersInput :: Int
  , movesInput :: Boolean
  , game :: Maybe Game
  , position :: Int
  , playing :: Boolean
  }

data Action
  = Initialize
  | SetSeedInput String
  | SetPlayers String
  | ToggleMoves Boolean
  | NewGame
  | RandomSeed
  | Scrub Int
  | StepBack
  | StepForward
  | JumpStart
  | JumpEnd
  | TogglePlay
  | Tick

currentKnowledge :: Game -> Int -> Knowledge
currentKnowledge game position =
  fromMaybe (emptyKnowledge defaultPlayerCount) (Array.index game.snapshots position)

-- | The event the timeline cursor sits just after; Nothing at the start.
currentEvent :: Game -> Int -> Maybe Event
currentEvent game position = Array.index game.result.log (position - 1)

maxPosition :: Game -> Int
maxPosition game = Array.length game.result.log
