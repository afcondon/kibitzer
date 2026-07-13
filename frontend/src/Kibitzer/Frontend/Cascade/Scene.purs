-- | Tree builders for the cascade view. The chrome (grid, labels,
-- | headers) is rendered once per game into `#cascade-view`; everything
-- | that moves is rebuilt as pure data every animation tick and rerendered
-- | into its own named group, so HATS diffs marks against marks and never
-- | touches the grid — the ForcePlayground recipe.
module Kibitzer.Frontend.Cascade.Scene
  ( EdgeLine
  , Bracket
  , StripBar
  , Verdict(..)
  , SceneInput
  , renderChrome
  , renderScene
  , clearScene
  , clearView
  , eventLabel
  , railTree
  , stripTree
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (maximum, minimum)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Hylograph.HATS (Tree, elem, forEach, onClick, staticStr, withBehaviors)
import Hylograph.HATS.Friendly as F
import Hylograph.HATS.InterpreterTick (clearContainer, rerender)
import Hylograph.Internal.Element.Types (ElementType(..))
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cards (allCards, displayName)
import Kibitzer.Describe (describeSuggestion, eventRef, playerName)
import Kibitzer.Event (Event(..), EventId(..))
import Kibitzer.Frontend.Cascade.Anim (Glyph(..), RenderMark)
import Kibitzer.Frontend.Cascade.Layout as L
import Kibitzer.Player (PlayerCount, PlayerId(..), playerCountToInt)

-- | A provenance hairline, premise cell to conclusion cell.
type EdgeLine =
  { key :: String
  , x1 :: Number
  , y1 :: Number
  , x2 :: Number
  , y2 :: Number
  , opacity :: Number
  , tip :: String
  }

-- | A live disjunction: a spine in the shower's column spanning its
-- | candidate rows.
type Bracket = { key :: String, x :: Number, ys :: Array Number }

type StripBar = { index :: Int, count :: Int, current :: Boolean }

type SceneInput =
  { marks :: Array RenderMark
  , edges :: Array EdgeLine
  , brackets :: Array Bracket
  , rail :: String
  , verdict :: Verdict
  , strip :: Array StripBar
  , onBar :: Int -> Effect Unit
  }

-- | The watcher's standing at the current position, shown above the
-- | sparkline: quiet progress while working, full credit once solved.
data Verdict = Working String | Solved String

ink :: String
ink = "#141414"

faint :: String
faint = "#ababab"

-- matches --accent in style.css
accent :: String
accent = "#d92b2b"

accentFaint :: String
accentFaint = "#e9a3a3"

hairline :: String
hairline = "#e6e6e6"

-- | Empty the whole cascade container. Called when switching between the
-- | packs and grid views: HATS diffs against whatever DOM it finds, and
-- | diffing one view's chrome against the other's leaves debris.
clearView :: Effect Unit
clearView = clearContainer "#cascade-view"

-- | The SVG skeleton: static chrome drawn once, then one empty named
-- | group per moving layer (z-order: edges under brackets under marks).
renderChrome :: PlayerCount -> Effect Unit
renderChrome count = do
  _ <- rerender "#cascade-view" (chromeTree count)
  pure unit

renderScene :: SceneInput -> Effect Unit
renderScene input = do
  _ <- rerender "#cascade-edges" (edgesTree input.edges)
  _ <- rerender "#cascade-brackets" (bracketsTree input.brackets)
  _ <- rerender "#cascade-marks" (marksTree input.marks)
  _ <- rerender "#cascade-rail" (railTree input.rail input.verdict)
  _ <- rerender "#cascade-strip" (stripTree input.onBar input.strip)
  pure unit

-- | Empty every moving layer (leaving chrome) — used on re-deal.
clearScene :: Effect Unit
clearScene = renderScene
  { marks: []
  , edges: []
  , brackets: []
  , rail: ""
  , verdict: Working ""
  , strip: []
  , onBar: \_ -> pure unit
  }

chromeTree :: PlayerCount -> Tree
chromeTree count =
  elem SVG
    [ F.viewBox 0.0 0.0 L.svgWidth L.svgHeight
    , F.attr "id" "cascade-svg"
    , F.preserveAspectRatio "xMidYMid meet"
    ]
    [ elem Group [ F.attr "id" "cascade-chrome" ] (gridChrome count)
    , elem Group [ F.attr "id" "cascade-edges" ] []
    , elem Group [ F.attr "id" "cascade-brackets" ] []
    , elem Group [ F.attr "id" "cascade-marks" ] []
    , elem Group [ F.attr "id" "cascade-rail" ] []
    , elem Group [ F.attr "id" "cascade-strip" ] []
    ]

gridChrome :: PlayerCount -> Array Tree
gridChrome count = rowLabels <> rowLines <> headers
  where
  gridLeft = L.labelRight + 8.0
  gridRight = L.columnX count (L.envelopeColumn count) + 26.0

  rowLabels = allCards # Array.mapWithIndex \i card ->
    elem Text
      [ F.x L.labelRight
      , F.y (L.rowY i + 4.0)
      , F.textAnchor "end"
      , F.fontSize "11"
      , F.fill "#555555"
      , staticStr "textContent" (displayName card)
      ]
      []

  rowLines = allCards # Array.mapWithIndex \i _ ->
    elem Line
      [ F.x1 gridLeft
      , F.y1 (L.rowY i + 12.0)
      , F.x2 gridRight
      , F.y2 (L.rowY i + 12.0)
      , F.stroke hairline
      , F.strokeWidth 1.0
      ]
      []

  headers =
    let
      seat j = elem Text
        [ F.x (L.columnX count j)
        , F.y (L.gridTop - 10.0)
        , F.textAnchor "middle"
        , F.fontSize "12"
        , F.fontWeight "600"
        , F.fill ink
        , staticStr "textContent" (playerName (PlayerId j))
        ]
        []
      env = elem Text
        [ F.x (L.columnX count (L.envelopeColumn count))
        , F.y (L.gridTop - 10.0)
        , F.textAnchor "middle"
        , F.fontSize "10"
        , F.fontWeight "600"
        , F.fill accent
        , staticStr "textContent" "ENV"
        ]
        []
    in
      Array.snoc (map seat (Array.range 0 (playerCountToInt count - 1))) env

marksTree :: Array RenderMark -> Tree
marksTree rmarks =
  forEach "marks" Group rmarks (_.mark.key) markTemplate

-- | One mark, its attributes a pure function of animation progress:
-- | entering marks fly in from the event rail and fade up; exiting marks
-- | fade out in place.
markTemplate :: RenderMark -> Tree
markTemplate rm =
  let
    p = case rm.enterProgress of
      Just raw -> Tick.easeOutCubic (clamp 0.0 1.0 raw)
      Nothing -> 1.0
    x = Tick.lerp L.railAnchor.x rm.mark.x p
    y = Tick.lerp L.railAnchor.y rm.mark.y p
    fade base = case rm.exitProgress of
      Just ep -> Tick.lerp base 0.0 ep
      Nothing -> base * p
    dot radius colour = elem Circle
      [ F.cx x
      , F.cy y
      , F.r (Tick.lerp (radius * 1.8) radius p)
      , F.fill colour
      , F.opacity (show (fade 1.0))
      ]
      []
    cross colour = elem Text
      [ F.x x
      , F.y (y + 4.5)
      , F.textAnchor "middle"
      , F.fontSize "14"
      , F.fill colour
      , F.opacity (show (fade 0.9))
      , staticStr "textContent" "×"
      ]
      []
  in
    elem Group []
      [ case rm.mark.glyph of
          GHolds -> dot 6.0 ink
          GEnvIn -> dot 7.5 accent
          GLacks -> cross faint
          GEnvOut -> cross accentFaint
      , elem Title [ staticStr "textContent" rm.mark.tip ] []
      ]

-- | Each edge is a visible hairline plus an invisible fat twin — a 1px
-- | line is unhoverable, and the provenance tooltip is the whole point.
edgesTree :: Array EdgeLine -> Tree
edgesTree edges =
  forEach "edges" Group edges _.key \e ->
    elem Group []
      [ elem Line
          [ F.x1 e.x1
          , F.y1 e.y1
          , F.x2 e.x2
          , F.y2 e.y2
          , F.stroke ink
          , F.strokeWidth 1.0
          , F.opacity (show e.opacity)
          ]
          []
      , elem Line
          [ F.x1 e.x1
          , F.y1 e.y1
          , F.x2 e.x2
          , F.y2 e.y2
          , F.stroke "transparent"
          , F.strokeWidth 9.0
          ]
          [ elem Title [ staticStr "textContent" e.tip ] [] ]
      ]

bracketsTree :: Array Bracket -> Tree
bracketsTree brackets =
  forEach "brackets" Group brackets _.key \b ->
    let
      yTop = fromMaybe 0.0 (minimum b.ys) - 8.0
      yBottom = fromMaybe 0.0 (maximum b.ys) + 8.0
      -- the spine is a whisper (candidates can sit in distant category
      -- blocks); the ticks at candidate rows carry the meaning
      spine = elem Line
        [ F.x1 b.x
        , F.y1 yTop
        , F.x2 b.x
        , F.y2 yBottom
        , F.stroke accent
        , F.strokeWidth 1.0
        , staticStr "stroke-dasharray" "2 4"
        , F.opacity "0.35"
        ]
        []
      tick y = elem Line
        [ F.x1 b.x
        , F.y1 y
        , F.x2 (b.x - 6.0)
        , F.y2 y
        , F.stroke accent
        , F.strokeWidth 1.4
        , F.opacity "0.6"
        ]
        []
    in
      elem Group [] (Array.cons spine (map tick b.ys))

railTree :: String -> Verdict -> Tree
railTree label verdict =
  elem Group []
    [ elem Text
        [ F.x L.railAnchor.x
        , F.y (L.railAnchor.y + 4.0)
        , F.textAnchor "start"
        , F.fontSize "13"
        , F.fontWeight "500"
        , F.fill ink
        , staticStr "textContent" label
        ]
        []
    , case verdict of
        Working text -> verdictText text "#767676" "400"
        Solved text -> verdictText text accent "600"
    ]
  where
  verdictText text colour weight = elem Text
    [ F.x L.railAnchor.x
    , F.y (L.stripTop - 12.0)
    , F.textAnchor "start"
    , F.fontSize "13"
    , F.fontWeight weight
    , F.fill colour
    , staticStr "textContent" text
    ]
    []

stripTree :: (Int -> Effect Unit) -> Array StripBar -> Tree
stripTree onBar bars =
  forEach "strip" Rect bars (\b -> "s" <> show b.index) \b ->
    let
      n = Array.length bars
      slot = L.stripSlot n b.index
      h = clamp 2.0 L.stripHeight (3.5 * toNumber b.count)
    in
      withBehaviors [ onClick (onBar b.index) ]
        $ elem Rect
            [ F.x slot.x
            , F.y (L.stripTop + L.stripHeight - h)
            , F.width slot.w
            , F.height h
            , F.fill (if b.current then accent else "#cfcfcf")
            , F.style "cursor: pointer;"
            ]
            []

-- | What the watcher may be told about the event the cursor sits after.
-- | Deliberately less than `describeEvent`, which names shown cards.
eventLabel :: Int -> Maybe Event -> String
eventLabel position = case _ of
  Nothing -> "Before the deal — the watcher knows nothing."
  Just e -> eventRef (EventId (position - 1)) <> " · " <> case e of
    GameDealt _ -> "cards dealt; three sealed in the envelope"
    Moved { player, roll } -> playerName player <> " rolls " <> show roll
    SuggestionMade { by, suggestion } ->
      playerName by <> " asks: " <> describeSuggestion suggestion
    Passed { player } -> playerName player <> " passes"
    CardShown { by, to } ->
      playerName by <> " shows " <> playerName to <> " a card — unseen"
    AccusationMade { by, correct } ->
      playerName by <> " accuses — " <> if correct then "correct" else "wrong"
