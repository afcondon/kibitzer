-- | The transport as a floating control block, pinned top-right. Four
-- | stacked rows — a wide play/pause, an EVENT step (back/forward through
-- | what happened), a DISCOVERY step (prev/next deduction the watcher
-- | worked out), and start/end — plus a slim scrubber and a position
-- | readout beneath. Stateless: everything it shows arrives as `Input`,
-- | every press leaves as `Output`. Event steps and start/end are just
-- | scrubs to computed positions (the parent clamps); the discovery steps
-- | need the parent's fact index, so they leave as their own intents.
module Kibitzer.Frontend.Component.TransportBar
  ( Input
  , Output(..)
  , Slot
  , component
  ) where

import Prelude

import Data.Const (Const)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

type Input = { position :: Int, max :: Int, playing :: Boolean }

data Output
  = Scrubbed Int
  | PlayToggled
  | PrevDiscovery
  | NextDiscovery

type Slot = H.Slot (Const Void) Output Unit

data Action
  = Receive Input
  | Raise Output

component :: forall q m. H.Component q Input Output m
component = H.mkComponent
  { initialState: identity
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }

handleAction :: forall m. Action -> H.HalogenM Input Action () Output m Unit
handleAction = case _ of
  Receive input -> H.put input
  Raise output -> H.raise output

render :: forall m. Input -> H.ComponentHTML Action () m
render { position, max: maxPos, playing } =
  HH.div [ HP.class_ (HH.ClassName "transport-float") ]
    [ HH.div [ HP.class_ (HH.ClassName "transport-rows") ]
        [ HH.div [ HP.classes (map HH.ClassName [ "transport-row", "play-row" ]) ]
            [ wideButton (if playing then "⏸ Pause" else "▶ Play") PlayToggled ]
        , stepRow "event" "‹ Back" (Scrubbed (position - 1)) "Forward ›" (Scrubbed (position + 1))
        , stepRow "deduction" "‹ Prev" PrevDiscovery "Next ›" NextDiscovery
        , HH.div [ HP.class_ (HH.ClassName "transport-row") ]
            [ button "⤒ Start" (Scrubbed 0)
            , button "End ⤓" (Scrubbed maxPos)
            ]
        ]
    , HH.input
        [ HP.type_ HP.InputRange
        , HP.min 0.0
        , HP.max (Int.toNumber maxPos)
        , HP.value (show position)
        , HE.onValueInput \s -> Raise (Scrubbed (fromMaybe position (Int.fromString s)))
        , HP.class_ (HH.ClassName "scrubber")
        ]
    , HH.span [ HP.class_ (HH.ClassName "position") ]
        [ HH.text (positionLabel <> " / E" <> show (maxPos - 1)) ]
    ]
  where
  positionLabel = if position == 0 then "—" else "E" <> show (position - 1)

-- | A labelled two-button stepper row: a small caption on the left names
-- | which kind of step this is (so the event and discovery pairs never
-- | get confused), then the back/forward buttons.
stepRow
  :: forall m
   . String
  -> String
  -> Output
  -> String
  -> Output
  -> H.ComponentHTML Action () m
stepRow caption backLabel backOut fwdLabel fwdOut =
  HH.div [ HP.classes (map HH.ClassName [ "transport-row", "step-row" ]) ]
    [ HH.span [ HP.class_ (HH.ClassName "row-caption") ] [ HH.text caption ]
    , button backLabel backOut
    , button fwdLabel fwdOut
    ]

button :: forall m. String -> Output -> H.ComponentHTML Action () m
button label output =
  HH.button
    [ HE.onClick \_ -> Raise output, HP.class_ (HH.ClassName "transport-btn") ]
    [ HH.text label ]

wideButton :: forall m. String -> Output -> H.ComponentHTML Action () m
wideButton label output =
  HH.button
    [ HE.onClick \_ -> Raise output
    , HP.classes (map HH.ClassName [ "transport-btn", "wide" ])
    ]
    [ HH.text label ]
