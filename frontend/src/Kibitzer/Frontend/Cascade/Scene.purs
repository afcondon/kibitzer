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
import Kibitzer.Frontend.Cascade.Radial as Radial
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
  { count :: PlayerCount
  , marks :: Array RenderMark
  , edges :: Array EdgeLine
  , brackets :: Array Bracket
  , bracketFade :: Number -- 1 = table view, 0 = fully morphed away
  , chromeFade :: Number -- ditto, for the notebook grid itself
  , dagLevels :: Array { y :: Number, label :: String }
  , dagOpacity :: Number -- the skyline's level axis fades in as the grid fades out
  , rings :: Array Radial.RingGuide
  , ringsOpacity :: Number -- ditto for the radial view's orbit guides
  , tokens :: Number -- 0 = notebook glyphs (✓/×), 1 = "E23" event tokens
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
  _ <- rerender "#cascade-chrome"
    (elem Group [ F.opacity (show input.chromeFade) ] (gridChrome input.count))
  _ <- rerender "#cascade-dagaxis" (dagAxisTree input.dagOpacity input.dagLevels)
  _ <- rerender "#cascade-rings" (ringsTree input.ringsOpacity input.rings)
  _ <- rerender "#cascade-edges" (edgesTree input.edges)
  _ <- rerender "#cascade-brackets" (bracketsTree input.bracketFade input.brackets)
  _ <- rerender "#cascade-marks" (marksTree input.tokens input.marks)
  _ <- rerender "#cascade-rail" (railTree input.rail input.verdict)
  _ <- rerender "#cascade-strip" (stripTree input.onBar input.strip)
  pure unit

chromeTree :: PlayerCount -> Tree
chromeTree count =
  elem SVG
    [ F.viewBox 0.0 0.0 L.svgWidth L.svgHeight
    , F.attr "id" "cascade-svg"
    , F.preserveAspectRatio "xMidYMid meet"
    ]
    [ elem Group [ F.attr "id" "cascade-chrome" ]
        [ elem Group [ F.opacity "1" ] (gridChrome count) ]
    , elem Group [ F.attr "id" "cascade-dagaxis" ] []
    , elem Group [ F.attr "id" "cascade-rings" ] []
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

marksTree :: Number -> Array RenderMark -> Tree
marksTree tokens rmarks =
  forEach "marks" Group rmarks (_.mark.key) (markTemplate tokens)

-- | One mark, its attributes a pure function of animation progress:
-- | entering marks fly in from the event rail and fade up; exiting marks
-- | fade out in place. `tokens` crossfades the vocabulary — notebook
-- | glyphs in the table and skyline, "E23" event tokens in the radial
-- | view (bare grey for eliminations, ring-stroked for located cards,
-- | inverted on the accent for envelope certainties). Whichever layer is
-- | fully faded is skipped, so the table's DOM stays what it was.
markTemplate :: Number -> RenderMark -> Tree
markTemplate tokens rm =
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
      , F.opacity (show (fade 1.0 * (1.0 - tokens)))
      ]
      []
    cross colour = elem Text
      [ F.x x
      , F.y (y + 4.5)
      , F.textAnchor "middle"
      , F.fontSize "14"
      , F.fill colour
      , F.opacity (show (fade 0.9 * (1.0 - tokens)))
      , staticStr "textContent" "×"
      ]
      []
    erefText size colour weight = elem Text
      [ F.x x
      , F.y (y + 2.6)
      , F.textAnchor "middle"
      , F.fontSize size
      , F.fontWeight weight
      , F.fill colour
      , F.opacity (show (fade 0.95 * tokens))
      , staticStr "textContent" rm.mark.eref
      ]
      []
    tokenRing radius fill stroke = elem Circle
      [ F.cx x
      , F.cy y
      , F.r radius
      , F.fill fill
      , F.stroke stroke
      , F.strokeWidth 1.3
      , F.opacity (show (fade 1.0 * tokens))
      ]
      []
    glyphLayer =
      if tokens > 0.995 then []
      else
        [ case rm.mark.glyph of
            GHolds -> dot 6.0 ink
            GEnvIn -> dot 7.5 accent
            GLacks -> cross faint
            GEnvOut -> cross accentFaint
        ]
    tokenLayer =
      if tokens < 0.005 then []
      else case rm.mark.glyph of
        GLacks -> [ erefText "8" "#9a9a9a" "400" ]
        GEnvOut -> [ erefText "8" accentFaint "500" ]
        GHolds -> [ tokenRing 10.0 "#ffffff" ink, erefText "7.5" ink "600" ]
        GEnvIn -> [ tokenRing 10.5 accent accent, erefText "7.5" "#ffffff" "600" ]
  in
    elem Group []
      ( glyphLayer <> tokenLayer
          <> [ elem Title [ staticStr "textContent" rm.mark.tip ] [] ]
      )

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

bracketsTree :: Number -> Array Bracket -> Tree
bracketsTree fade brackets =
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
        , F.opacity (show (0.35 * fade))
        ]
        []
      tick y = elem Line
        [ F.x1 b.x
        , F.y1 y
        , F.x2 (b.x - 6.0)
        , F.y2 y
        , F.stroke accent
        , F.strokeWidth 1.4
        , F.opacity (show (0.6 * fade))
        ]
        []
    in
      elem Group [] (Array.cons spine (map tick b.ys))

-- | The DAG view's chrome: one hairline + caption per derivation level,
-- | fading in as the notebook fades out.
dagAxisTree :: Number -> Array { y :: Number, label :: String } -> Tree
dagAxisTree opacity levels =
  forEach "dagaxis" Group levels (\l -> "lvl" <> l.label) \l ->
    elem Group []
      [ elem Line
          [ F.x1 36.0
          , F.y1 l.y
          , F.x2 (svgWidthLocal - 36.0)
          , F.y2 l.y
          , F.stroke hairline
          , F.strokeWidth 1.0
          , F.opacity (show opacity)
          ]
          []
      -- captions at the right edge, clear of the crowded ground row
      , elem Text
          [ F.x (svgWidthLocal - 36.0)
          , F.y (l.y - 6.0)
          , F.textAnchor "end"
          , F.fontSize "10"
          , F.fill "#767676"
          , F.opacity (show opacity)
          , staticStr "textContent" l.label
          ]
          []
      ]
  where
  svgWidthLocal = L.svgWidth

-- | The radial view's chrome: one orbit guide per derivation ring plus
-- | the dashed bullseye where envelope certainties land, fading in as
-- | the notebook fades out.
ringsTree :: Number -> Array Radial.RingGuide -> Tree
ringsTree opacity rings =
  forEach "rings" Group rings (\g -> "ring" <> show g.r) \g ->
    let
      circleAttrs =
        [ F.cx Radial.centre.x
        , F.cy Radial.centre.y
        , F.r g.r
        , F.fill "none"
        , F.stroke (if g.bullseye then accent else hairline)
        , F.strokeWidth 1.0
        , F.opacity (show (opacity * if g.bullseye then 0.55 else 1.0))
        ]
      dash = if g.bullseye then [ staticStr "stroke-dasharray" "2 4" ] else []
      -- the bullseye's caption hangs below its guide; the certainties
      -- cluster at the centre itself
      caption = elem Text
        [ F.x Radial.centre.x
        , F.y (if g.bullseye then Radial.centre.y + g.r + 22.0 else Radial.centre.y - g.r - 5.0)
        , F.textAnchor "middle"
        , F.fontSize "10"
        , F.fill (if g.bullseye then accent else "#767676")
        , F.opacity (show (opacity * 0.9))
        , staticStr "textContent" g.label
        ]
        []
    in
      elem Group []
        ( Array.cons (elem Circle (circleAttrs <> dash) [])
            (if g.label == "" then [] else [ caption ])
        )

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
