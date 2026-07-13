-- | Rendering for the possibility packs. Same architecture as the grid
-- | cascade: chrome once per game, per-position layers (orbit guides,
-- | rail, sparkline) on scrub, and the bubbles rebuilt as pure data every
-- | animation frame from the simulation's live positions.
module Kibitzer.Frontend.Packs.View
  ( PacksAnim
  , ExitBubble
  , emptyPacksAnim
  , packsAnimActive
  , tickPacksAnim
  , renderPacksChrome
  , renderPacksPosition
  , renderPacksFrame
  ) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Hylograph.HATS (Tree, elem, forEach, staticStr)
import Hylograph.HATS.Friendly as F
import Hylograph.HATS.InterpreterTick (rerender)
import Hylograph.Internal.Element.Types (ElementType(..))
import Hylograph.Transition.Tick (Progress, Transitioning)
import Hylograph.Transition.Tick as Tick
import Kibitzer.Describe (playerName)
import Kibitzer.Frontend.Cascade.Layout (svgHeight, svgWidth)
import Kibitzer.Frontend.Cascade.Scene (StripBar, Verdict, railTree, stripTree)
import Kibitzer.Frontend.Packs.Model (PackNode, PossInfo, PossState(..), anchorFor, bubbleRadius, categoryColour, envelopeLoc, orbitRadius)
import Kibitzer.Player (PlayerCount, PlayerId(..), playerCountToInt)

-- | A possibility mid-departure: frozen where it died, flying toward the
-- | node that absorbed it (the confirmed copy of the same card), or
-- | simply fading if the card's location is not the reason it left.
type ExitBubble =
  { id :: Int
  , x :: Number
  , y :: Number
  , card :: Int
  , targetId :: Maybe Int
  }

type PacksAnim =
  { entering :: Map Int Progress
  , exiting :: Array (Transitioning ExitBubble)
  }

emptyPacksAnim :: PacksAnim
emptyPacksAnim = { entering: Map.empty, exiting: [] }

packsAnimActive :: PacksAnim -> Boolean
packsAnimActive anim = not (Map.isEmpty anim.entering) || not (Array.null anim.exiting)

tickPacksAnim :: Number -> PacksAnim -> PacksAnim
tickPacksAnim delta anim =
  { entering: (Tick.tickProgressMap delta anim.entering).active
  , exiting: (Tick.tickTransitions (delta * 0.8) anim.exiting).active
  }

ink :: String
ink = "#141414"

accent :: String
accent = "#d92b2b"

-- | The SVG skeleton: envelope round-rect and seat letters as chrome,
-- | empty named groups for the moving layers.
renderPacksChrome :: PlayerCount -> Effect Unit
renderPacksChrome count = do
  _ <- rerender "#cascade-view" (chromeTree count)
  pure unit

chromeTree :: PlayerCount -> Tree
chromeTree count =
  elem SVG
    [ F.viewBox 0.0 0.0 svgWidth svgHeight
    , F.attr "id" "packs-svg"
    , F.preserveAspectRatio "xMidYMid meet"
    ]
    [ elem Group [ F.attr "id" "packs-chrome" ] (seatLabels <> [ envelopeRect ])
    , elem Group [ F.attr "id" "packs-orbits" ] []
    , elem Group [ F.attr "id" "packs-bubbles" ] []
    , elem Group [ F.attr "id" "cascade-rail" ] []
    , elem Group [ F.attr "id" "cascade-strip" ] []
    ]
  where
  seatLabels = Array.range 0 (playerCountToInt count - 1) # map \j ->
    let
      a = anchorFor count j
    in
      elem Text
        [ F.x a.x
        , F.y (a.y - orbitRadius - 14.0)
        , F.textAnchor "middle"
        , F.fontSize "13"
        , F.fontWeight "600"
        , F.fill ink
        , staticStr "textContent" (playerName (PlayerId j))
        ]
        []

  -- the non-animating mark of the envelope at the heart of the table
  envelopeRect =
    let
      a = anchorFor count (envelopeLoc count)
    in
      elem Group []
        [ elem Rect
            [ F.x (a.x - 52.0)
            , F.y (a.y - 40.0)
            , F.width 104.0
            , F.height 80.0
            , F.attr "rx" "12"
            , F.fill "none"
            , F.stroke accent
            , F.strokeWidth 1.4
            , F.opacity "0.8"
            ]
            []
        , elem Text
            [ F.x a.x
            , F.y (a.y - 48.0)
            , F.textAnchor "middle"
            , F.fontSize "10"
            , F.fontWeight "600"
            , F.fill accent
            , staticStr "textContent" "THE ENVELOPE"
            ]
            []
        ]

-- | The per-position layers: dashed orbit guides where a pack has live
-- | disjunction candidates, plus the shared rail/verdict and sparkline.
renderPacksPosition
  :: { count :: PlayerCount
     , orbits :: Map Int (Set Int)
     , rail :: String
     , verdict :: Verdict
     , strip :: Array StripBar
     , onBar :: Int -> Effect Unit
     }
  -> Effect Unit
renderPacksPosition input = do
  _ <- rerender "#packs-orbits" (orbitGuides input.count input.orbits)
  _ <- rerender "#cascade-rail" (railTree input.rail input.verdict)
  _ <- rerender "#cascade-strip" (stripTree input.onBar input.strip)
  pure unit

orbitGuides :: PlayerCount -> Map Int (Set Int) -> Tree
orbitGuides count orbits =
  forEach "orbit-guides" Circle live (\(loc /\ _) -> "og" <> show loc) \(loc /\ _) ->
    let
      a = anchorFor count loc
    in
      elem Circle
        [ F.cx a.x
        , F.cy a.y
        , F.r orbitRadius
        , F.fill "none"
        , F.stroke accent
        , F.strokeWidth 1.0
        , staticStr "stroke-dasharray" "3 5"
        , F.opacity "0.4"
        ]
        []
  where
  live = Array.filter (\(_ /\ s) -> not (Set.isEmpty s))
    (Map.toUnfoldable orbits :: Array _)

-- | One animation frame of bubbles: live possibilities at their sim
-- | positions, plus departures chasing the live position of the copy
-- | that absorbed them.
renderPacksFrame
  :: { envLoc :: Int
     , nodes :: Array PackNode
     , states :: Map Int PossInfo
     , anim :: PacksAnim
     }
  -> Effect Unit
renderPacksFrame { envLoc, nodes, states, anim } = do
  _ <- rerender "#packs-bubbles" (forEach "bubbles" Circle bubbles _.key template)
  pure unit
  where
  positionOf :: Int -> Maybe { x :: Number, y :: Number }
  positionOf i = map (\n -> { x: n.x, y: n.y }) (Array.find (\n -> n.id == i) nodes)

  bubbles = Array.mapMaybe live nodes <> map dying anim.exiting

  live n = case Map.lookup n.id states of
    Just info | info.state /= Gone ->
      let
        enter = fromMaybe 1.0 (map (clamp 0.0 1.0) (Map.lookup n.id anim.entering))
        pop = Tick.easeOutCubic enter
        base = case info.state of
          Ghost -> { opacity: 0.28, stroke: "none", strokeW: 0.0 }
          Confirmed ->
            { opacity: 1.0
            , stroke: if n.loc == envLoc then accent else ink
            , strokeW: 2.2
            }
          _ -> { opacity: 0.9, stroke: "none", strokeW: 0.0 }
      in
        Just
          { key: "p" <> show n.id
          , x: n.x
          , y: n.y
          , r: bubbleRadius * pop
          , fill: categoryColour n.card
          , opacity: base.opacity * pop
          , stroke: base.stroke
          , strokeW: base.strokeW
          , tip: info.tip
          }
    _ -> Nothing

  -- convergence: gather speed into the absorbing copy
  dying t =
    let
      eased = Tick.easeInCubic t.progress
      target = fromMaybe { x: t.item.x, y: t.item.y }
        (positionOf =<< t.item.targetId)
    in
      { key: "x" <> show t.item.id
      , x: Tick.lerp t.item.x target.x eased
      , y: Tick.lerp t.item.y target.y eased
      , r: Tick.lerp bubbleRadius 2.0 eased
      , fill: categoryColour t.item.card
      , opacity: Tick.lerp 0.85 0.15 t.progress
      , stroke: "none"
      , strokeW: 0.0
      , tip: ""
      }

  template b =
    elem Circle
      [ F.cx b.x
      , F.cy b.y
      , F.r b.r
      , F.fill b.fill
      , F.opacity (show b.opacity)
      , F.stroke b.stroke
      , F.strokeWidth b.strokeW
      ]
      (if b.tip == "" then [] else [ elem Title [ staticStr "textContent" b.tip ] [] ])
