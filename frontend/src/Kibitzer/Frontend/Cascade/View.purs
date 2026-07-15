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
import Data.String as String
import Effect (Effect)
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cards (Card)
import Kibitzer.Cascade (globalDepths)
import Kibitzer.Describe (describeClaim, describeFact, describeSuggestion, eventRef)
import Kibitzer.Event (EventId(..), eventIdToInt)
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim, renderMarks)
import Kibitzer.Frontend.Cascade.Layout as L
import Kibitzer.Frontend.Cascade.Radial as Radial
import Kibitzer.Frontend.Cascade.Scene (Bracket, EdgeLine, StripBar, Verdict(..), eventLabel, renderScene)
import Kibitzer.Frontend.Crossref as Crossref
import Kibitzer.Frontend.Types (Game, currentEvent, currentKnowledge)
import Kibitzer.Knowledge (Disjunction(..), Fact, FactId(..), envelopeIn, facts, solutionIfKnown)
import Kibitzer.Player (PlayerId(..))

redraw
  :: { game :: Game
     , position :: Int
     , wiring :: Boolean
     , layout :: { from :: L.GridLayout, to :: L.GridLayout, t :: Number }
     , radialPos :: Map Int { x :: Number, y :: Number } -- live orbit positions by fact id
     , hover :: Maybe Crossref.Implicated -- the cross-reference emphasis, if anything is hovered
     , anim :: CascadeAnim
     , onBar :: Int -> Effect Unit
     , onHoverFact :: Maybe Int -> Effect Unit
     }
  -> Effect Unit
redraw { game, position, wiring, layout, radialPos, hover, anim, onBar, onHoverFact } = renderScene
  { count
  , marks
  , edges
  , brackets
  , bracketFade: tableAmount
  , chromeFade: tableAmount
  , dagLevels
  , dagOpacity: skylineAmount * 0.85
  , rings: Radial.ringGuides maxDepth
  , ringsOpacity: radialAmount * 0.85
  , tokens: radialAmount
  , onHoverFact
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

  m = Tick.easeInOutCubic (clamp 0.0 1.0 layout.t)

  -- how much of layout l is showing this frame, 0..1
  amountOf :: L.GridLayout -> Number
  amountOf l = Tick.lerp
    (if layout.from == l then 1.0 else 0.0)
    (if layout.to == l then 1.0 else 0.0)
    m

  tableAmount = amountOf L.TableView
  skylineAmount = amountOf L.SkylineView
  radialAmount = amountOf L.RadialView

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

  -- a fact's home in one layout: notebook cell, skyline slot, or its
  -- live position in the orbit simulation (analytic radial fallback
  -- until the sim has spoken)
  homeOf :: L.GridLayout -> Fact -> { x :: Number, y :: Number }
  homeOf l f = case l of
    L.TableView -> L.claimCell count f.claim
    L.SkylineView -> dagPosOf f
    L.RadialView ->
      let
        FactId n = f.id
      in
        fromMaybe
          (Radial.analyticPos dagDepth maxDepth (Array.length allFacts) f)
          (Map.lookup n radialPos)

  -- a fact's position this frame: between its two homes of the moment
  posOf :: Fact -> { x :: Number, y :: Number }
  posOf f =
    let
      a = homeOf layout.from f
      b = homeOf layout.to f
    in
      { x: Tick.lerp a.x b.x m, y: Tick.lerp a.y b.y m }

  -- the hover emphasis is live only when the hovered thing implicates
  -- at least one visible fact
  hoverFacts :: Maybe (Set.Set Int)
  hoverFacts = case hover of
    Just imp | not (Set.isEmpty imp.facts) -> Just imp.facts
    _ -> Nothing

  -- every mark — the living and the dying alike — is repositioned into
  -- the current layout, so backward scrubs fade facts out where they
  -- stood, not at their table cell; the cross-reference emphasis rides
  -- along
  marks = renderMarks count visible anim <#> \rm0 ->
    let
      rm = case hoverFacts of
        Nothing -> rm0
        Just fs ->
          let hit = Set.member rm0.mark.fid fs
          in rm0 { lit = hit, dimmed = not hit }
    in
      case factOfKey rm.mark.key of
        Just f -> let p = posOf f in rm { mark = rm.mark { x = p.x, y = p.y } }
        Nothing -> rm

  factOfKey :: String -> Maybe Fact
  factOfKey key = do
    n <- Int.fromString (String.drop 1 key)
    Array.index allFacts n

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
    baseOpacity <- case Map.lookup ("f" <> show toN) anim.entering of
      Just p -> Just (Tick.lerpClamped 0.0 0.75 (Tick.easeOutCubic (clamp 0.0 1.0 p)))
      Nothing ->
        let
          -- away from the table the edges ARE the picture (skyline and
          -- radial alike), so the morph raises them even with wiring off
          settled = max (if wiring then 0.12 else 0.0) (0.3 * (1.0 - tableAmount))
        in
          if settled > 0.005 then Just settled else Nothing
    -- hover: edges inside the implicated ancestry come forward, the
    -- rest recede
    let
      opacity = case hoverFacts of
        Nothing -> baseOpacity
        Just fs ->
          if Set.member fromN fs && Set.member toN fs then max baseOpacity 0.7
          else baseOpacity * 0.12
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
