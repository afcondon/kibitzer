-- | Assembles one tick's SceneInput from the game and the animation
-- | state, and hands it to the Scene renderers. This is the only module
-- | that knows both what the frontend state looks like and what the
-- | cascade wants to draw.
module Kibitzer.Frontend.Cascade.View
  ( redraw
  , verdictFor
  , stripFor
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (maximum)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Set as Set
import Effect (Effect)
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cards (Card)
import Kibitzer.Cascade (globalDepths)
import Kibitzer.Describe (describeClaim, describeFact, describeSuggestion, eventRef)
import Kibitzer.Event (EventId(..), eventIdToInt)
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim, renderMarks)
import Kibitzer.Frontend.Cascade.Layout as L
import Kibitzer.Frontend.Cascade.Scene (Bracket, EdgeLine, StripBar, Verdict(..), eventLabel, renderScene)
import Kibitzer.Frontend.Types (Game, currentEvent, currentKnowledge)
import Kibitzer.Knowledge (Disjunction(..), Fact, FactId(..), envelopeIn, facts, solutionIfKnown)
import Kibitzer.Player (PlayerId(..))

redraw
  :: { game :: Game
     , position :: Int
     , wiring :: Boolean
     , morph :: Number -- 0 = notebook table, 1 = derivation DAG
     , anim :: CascadeAnim
     , onBar :: Int -> Effect Unit
     }
  -> Effect Unit
redraw { game, position, wiring, morph, anim, onBar } = renderScene
  { count
  , marks
  , edges
  , brackets
  , bracketFade: 1.0 - m
  , chromeFade: 1.0 - m
  , dagLevels
  , dagOpacity: m * 0.85
  , rail: eventLabel position (currentEvent game position)
  , verdict: verdictFor game position
  , strip: stripFor game position
  , onBar
  }
  where
  count = game.result.playerCount
  knowledge = currentKnowledge game position
  visible = facts knowledge
  visibleCount = Array.length visible

  m = Tick.easeInOutCubic (clamp 0.0 1.0 morph)

  -- every fact of the finished game, indexable by dense FactId
  allFacts :: Array Fact
  allFacts = fromMaybe [] (map facts (Array.last game.snapshots))

  -- the same marks in their second home: the derivation DAG, feed order
  -- along x, global derivation depth as the level
  dagDepth :: Map FactId Int
  dagDepth = globalDepths allFacts

  maxDepth :: Int
  maxDepth = fromMaybe 0 (maximum (Map.values dagDepth))

  levelGap :: Number
  levelGap = min 130.0 (440.0 / Int.toNumber (max 1 maxDepth))

  levelY :: Int -> Number
  levelY d = 570.0 - Int.toNumber d * levelGap

  dagLevels :: Array { y :: Number, label :: String }
  dagLevels = Array.range 0 maxDepth <#> \d ->
    { y: levelY d
    , label: if d == 0 then "observed directly" else "derived, " <> show d <> " deep"
    }

  dagPosOf :: Fact -> { x :: Number, y :: Number }
  dagPosOf f =
    let
      FactId n = f.id
      total = Int.toNumber (max 1 (Array.length allFacts))
    in
      { x: 40.0 + (Int.toNumber n + 0.5) / total * (L.svgWidth - 80.0)
      , y: levelY (fromMaybe 0 (Map.lookup f.id dagDepth))
      }

  -- a fact's home for this frame: between its notebook cell and its DAG slot
  posOf :: Fact -> { x :: Number, y :: Number }
  posOf f =
    let
      t = L.claimCell count f.claim
      g = dagPosOf f
    in
      { x: Tick.lerp t.x g.x m, y: Tick.lerp t.y g.y m }

  marks =
    Array.zipWith
      ( \f rm ->
          let p = posOf f in rm { mark = rm.mark { x = p.x, y = p.y } }
      )
      visible
      baseMarks
      <> Array.drop (Array.length visible) baseMarks
    where
    baseMarks = renderMarks count visible anim

  -- a hairline is bright while its conclusion flies in, then settles to
  -- faint persistent wiring (or nothing, with the toggle off)
  -- in the DAG the edges ARE the picture, so the morph raises them even
  -- with the wiring toggle off
  edges :: Array EdgeLine
  edges = game.allEdges # Array.mapMaybe \e -> do
    let FactId toN = e.to
    let FactId fromN = e.from
    guardVisible toN
    fromFact <- Array.index allFacts fromN
    toFact <- Array.index allFacts toN
    let from = posOf fromFact
    let to = posOf toFact
    opacity <- case Map.lookup ("f" <> show toN) anim.entering of
      Just p -> Just (Tick.lerpClamped 0.0 0.75 (Tick.easeOutCubic (clamp 0.0 1.0 p)))
      Nothing ->
        let
          settled = max (if wiring then 0.12 else 0.0) (0.3 * m)
        in
          if settled > 0.005 then Just settled else Nothing
    pure
      { key: "e" <> show fromN <> "-" <> show toN
      , x1: from.x
      , y1: from.y
      , x2: to.x
      , y2: to.y
      , opacity
      , tip: describeClaim fromFact.claim <> "  ⟶  " <> describeFact toFact
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

-- | The credit line: the full solution once the envelope is determined
-- | (with the moment it happened), quiet progress until then. Shared by
-- | both cascade views.
verdictFor :: Game -> Int -> Verdict
verdictFor game position = case solutionIfKnown knowledge of
  Just solution ->
    Solved
      ( "The watcher has it: " <> describeSuggestion solution
          <> case Array.findIndex (isJust <<< solutionIfKnown) game.snapshots of
            Just p | p >= 1 -> " — known since " <> eventRef (EventId (p - 1)) <> "."
            _ -> "."
      )
  Nothing ->
    Working ("Envelope determined: " <> show (Set.size (envelopeIn knowledge)) <> " of 3.")
  where
  knowledge = currentKnowledge game position

-- | Facts-per-event sparkline bars, shared by both cascade views.
stripFor :: Game -> Int -> Array StripBar
stripFor game position = game.cascades # Array.mapWithIndex \i fr ->
  { index: i, count: Array.length fr.newFacts, current: i == position }
