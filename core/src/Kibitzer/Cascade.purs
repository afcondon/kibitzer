-- | The derivation cascade: what each event's processing added to a mind,
-- | shaped for animation. A frame holds the facts born at one timeline
-- | position, each with its depth in that frame's derivation DAG (0 =
-- | recorded straight off the observation, deeper = derived from facts
-- | born moments earlier in the same avalanche), the premise edges, and
-- | the live disjunctions. Computed once per game, like
-- | `knowledgeTimeline`; scrubbing then just indexes.
module Kibitzer.Cascade
  ( CascadeEdge
  , CascadeFrame
  , cascadeTimeline
  , globalDepths
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl, maximum)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Kibitzer.Event (Log)
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (Disjunction, Fact, FactId, Knowledge, disjunctions, factCount, facts)
import Kibitzer.Observe (Perspective)
import Kibitzer.Player (PlayerCount)

type CascadeEdge = { from :: FactId, to :: FactId }

type CascadeFrame =
  { newFacts :: Array Fact -- born at this position, sorted by (depth, id)
  , depth :: Map FactId Int -- longest premise chain within the frame
  , edges :: Array CascadeEdge -- premise → conclusion, reaching into older facts too
  , disjunctions :: Array Disjunction -- live state at this position
  }

-- | One frame per timeline position — |log|+1 of them, index-aligned with
-- | `knowledgeTimeline`, so the two are scrubbed together.
cascadeTimeline :: PlayerCount -> Perspective -> Log -> Array CascadeFrame
cascadeTimeline count perspective log =
  case Array.uncons minds of
    Nothing -> []
    Just { head } ->
      Array.cons (restFrame head) (map frame (Array.zip minds (Array.drop 1 minds)))
  where
  minds = knowledgeTimeline count perspective log

-- | Depth of every fact in the whole game's derivation DAG (longest
-- | premise chain from direct observations). Premises always carry
-- | smaller ids, so one left fold in feed order suffices. This is the
-- | y-axis of the DAG view; frame-local depths above drive staggering.
globalDepths :: Array Fact -> Map FactId Int
globalDepths = foldl
  ( \acc f -> Map.insert f.id
      ( case Array.mapMaybe (\p -> Map.lookup p acc) f.justification.premises of
          [] -> 0
          ds -> 1 + fromMaybe 0 (maximum ds)
      )
      acc
  )
  Map.empty

-- | A position at which nothing was learned (position 0, always).
restFrame :: Knowledge -> CascadeFrame
restFrame knowledge =
  { newFacts: [], depth: Map.empty, edges: [], disjunctions: disjunctions knowledge }

frame :: Tuple Knowledge Knowledge -> CascadeFrame
frame (Tuple before after) =
  { newFacts: Array.sortWith (\f -> depthOf f /\ f.id) born
  , depth
  , edges: Array.concatMap
      (\f -> map (\from -> { from, to: f.id }) f.justification.premises)
      born
  , disjunctions: disjunctions after
  }
  where
  born = Array.drop (factCount before) (facts after)

  -- Premises always carry smaller ids, so a left fold in feed order sees
  -- every in-frame premise's depth before it needs it; premises from
  -- earlier frames miss the map and count as ground.
  depth :: Map FactId Int
  depth = foldl
    ( \acc f -> Map.insert f.id
        ( case Array.mapMaybe (\p -> Map.lookup p acc) f.justification.premises of
            [] -> 0
            ds -> 1 + fromMaybe 0 (maximum ds)
        )
        acc
    )
    Map.empty
    born

  depthOf :: Fact -> Int
  depthOf f = fromMaybe 0 (Map.lookup f.id depth)
