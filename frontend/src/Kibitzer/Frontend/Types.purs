-- | Shared state and action types for the frontend. The design principle:
-- | `snapshots` holds the watcher's knowledge at every position, computed
-- | once per game by `knowledgeTimeline`; every render merely indexes it,
-- | so scrubbing anywhere on the timeline is O(1).
module Kibitzer.Frontend.Types
  ( Game
  , State
  , Tab(..)
  , Action(..)
  , currentKnowledge
  , currentEvent
  , maxPosition
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Maybe (Maybe, fromMaybe)
import Halogen.Subscription as HS
import Hylograph.Simulation (SimulationHandle)
import Kibitzer.Board (Position)
import Kibitzer.Cascade (CascadeEdge, CascadeFrame)
import Kibitzer.Event (Event)
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim)
import Kibitzer.Frontend.Packs.Model (PackRow, PossInfo)
import Kibitzer.Frontend.Packs.View (PacksAnim)
import Kibitzer.Game (Result)
import Kibitzer.Knowledge (FactId, Knowledge, emptyKnowledge)
import Kibitzer.Player (PlayerId, defaultPlayerCount)

type Game =
  { seedInt :: Int
  , result :: Result
  , snapshots :: Array Knowledge
  , positions :: Array (Map PlayerId Position) -- index-aligned with snapshots
  , cascades :: Array CascadeFrame -- also index-aligned; the watcher's derivation frames
  , depths :: Map FactId Int -- frame-local derivation depth of every fact
  , allEdges :: Array CascadeEdge -- the complete premise DAG of the finished game
  }

data Tab = PlayTab | CascadeTab | AboutTab | CodeTab

derive instance Eq Tab

type State =
  { seedInput :: String
  , playersInput :: Int
  , movesInput :: Boolean
  , game :: Maybe Game
  , position :: Int
  , playing :: Boolean
  , tab :: Tab
  , cascadeAnim :: CascadeAnim
  , animPending :: Boolean -- an animation frame is already scheduled
  , animListener :: Maybe (HS.Listener Action)
  , wiring :: Boolean -- keep settled provenance hairlines visible
  , dagView :: Boolean -- grid sub-view: morph the notebook into the derivation DAG
  , dagMorph :: Number -- 0 = table, 1 = DAG; animated between
  , packView :: Boolean -- Cascade tab: possibility packs (true) or the grid
  , simHandle :: Maybe (SimulationHandle PackRow)
  , packStates :: Map Int PossInfo -- possibility states at the current position
  , packsAnim :: PacksAnim
  }

data Action
  = Initialize
  | SetTab Tab
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
  | AnimTick
  | ToggleWiring Boolean
  | ToggleDag Boolean
  | SetPackView Boolean

currentKnowledge :: Game -> Int -> Knowledge
currentKnowledge game position =
  fromMaybe (emptyKnowledge defaultPlayerCount) (Array.index game.snapshots position)

-- | The event the timeline cursor sits just after; Nothing at the start.
currentEvent :: Game -> Int -> Maybe Event
currentEvent game position = Array.index game.result.log (position - 1)

maxPosition :: Game -> Int
maxPosition game = Array.length game.result.log
