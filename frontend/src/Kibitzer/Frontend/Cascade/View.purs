-- | Assembles one tick's SceneInput from the game and the animation
-- | state, and hands it to the Scene renderers. This is the only module
-- | that knows both what the frontend state looks like and what the
-- | cascade wants to draw.
module Kibitzer.Frontend.Cascade.View
  ( redraw
  ) where

import Prelude

import Data.Array as Array
import Data.Int as Int
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Effect (Effect)
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cards (Card)
import Kibitzer.Event (eventIdToInt)
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim, factKey, renderMarks)
import Kibitzer.Frontend.Cascade.Layout as L
import Kibitzer.Frontend.Cascade.Scene (Bracket, EdgeLine, StripBar, eventLabel, renderScene)
import Kibitzer.Frontend.Types (Game, currentEvent, currentKnowledge)
import Kibitzer.Knowledge (Disjunction(..), Fact, FactId(..), facts)
import Kibitzer.Player (PlayerId(..))

redraw
  :: { game :: Game
     , position :: Int
     , wiring :: Boolean
     , anim :: CascadeAnim
     , onBar :: Int -> Effect Unit
     }
  -> Effect Unit
redraw { game, position, wiring, anim, onBar } = renderScene
  { marks: renderMarks count visible anim
  , edges
  , brackets
  , rail: eventLabel position (currentEvent game position)
  , strip
  , onBar
  }
  where
  count = game.result.playerCount
  visible = facts (currentKnowledge game position)
  visibleCount = Array.length visible

  -- every fact of the finished game, indexable by dense FactId
  allFacts :: Array Fact
  allFacts = fromMaybe [] (map facts (Array.last game.snapshots))

  cellOf :: FactId -> Maybe { x :: Number, y :: Number }
  cellOf fid@(FactId n) = do
    f <- Array.index allFacts n
    if f.id == fid then Just (L.claimCell count f.claim) else Nothing

  -- a hairline is bright while its conclusion flies in, then settles to
  -- faint persistent wiring (or nothing, with the toggle off)
  edges :: Array EdgeLine
  edges = game.allEdges # Array.mapMaybe \e -> do
    let FactId toN = e.to
    let FactId fromN = e.from
    guardVisible toN
    from <- cellOf e.from
    to <- cellOf e.to
    opacity <- case Map.lookup ("f" <> show toN) anim.entering of
      Just p -> Just (Tick.lerpClamped 0.0 0.75 (Tick.easeOutCubic (clamp 0.0 1.0 p)))
      Nothing -> if wiring then Just 0.12 else Nothing
    pure
      { key: "e" <> show fromN <> "-" <> show toN
      , x1: from.x
      , y1: from.y
      , x2: to.x
      , y2: to.y
      , opacity
      }
    where
    guardVisible n = if n < visibleCount then Just unit else Nothing

  -- several live disjunctions can share a column; each sits a step
  -- further from the cell centre so its ticks stay readable
  brackets :: Array Bracket
  brackets = case Array.index game.cascades position of
    Nothing -> []
    Just fr ->
      let
        live = fr.disjunctions # Array.mapMaybe case _ of
          Disjunction d | not d.resolved, Set.size d.candidates >= 2 -> Just d
          _ -> Nothing
      in
        live # Array.mapWithIndex \i d ->
          let
            PlayerId p = d.player
            siblings = Array.length
              (Array.filter (\e -> e.player == d.player) (Array.take i live))
          in
            { key: "d" <> show (eventIdToInt d.source)
            , x: L.columnX count p + 14.0 + 4.0 * Int.toNumber siblings
            , ys: map rowCentre (Set.toUnfoldable d.candidates)
            }

  rowCentre :: Card -> Number
  rowCentre c = L.rowY (L.rowIndex c)

  strip :: Array StripBar
  strip = game.cascades # Array.mapWithIndex \i fr ->
    { index: i, count: Array.length fr.newFacts, current: i == position }
