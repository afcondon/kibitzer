-- | The scrubber. Because every position's knowledge is a precomputed
-- | snapshot, dragging anywhere is instant.
module Kibitzer.Frontend.View.Timeline (timelinePane) where

import Prelude

import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Kibitzer.Describe (describeEvent)
import Kibitzer.Frontend.Types (Action(..), Game, currentEvent, maxPosition)

timelinePane :: forall w. Game -> Int -> Boolean -> HH.HTML w Action
timelinePane game position playing =
  HH.footer [ HP.class_ (HH.ClassName "timeline") ]
    [ HH.div [ HP.class_ (HH.ClassName "transport") ]
        [ button "⏮" JumpStart
        , button "◀" StepBack
        , button (if playing then "⏸" else "▶") TogglePlay
        , button "▶▶" StepForward
        , button "⏭" JumpEnd
        ]
    , HH.input
        [ HP.type_ HP.InputRange
        , HP.min 0.0
        , HP.max (Int.toNumber (maxPosition game))
        , HP.value (show position)
        , HE.onValueInput \s -> Scrub (fromMaybe position (Int.fromString s))
        , HP.class_ (HH.ClassName "scrubber")
        ]
    , HH.div [ HP.class_ (HH.ClassName "timeline-caption") ]
        [ HH.span [ HP.class_ (HH.ClassName "position") ]
            [ HH.text (positionLabel <> " / E" <> show (maxPosition game - 1)) ]
        , HH.span_
            [ HH.text case currentEvent game position of
                Just event -> describeEvent event
                Nothing -> "Start — nothing has happened yet."
            ]
        ]
    ]
  where
  positionLabel = if position == 0 then "—" else "E" <> show (position - 1)

button :: forall w. String -> Action -> HH.HTML w Action
button label action =
  HH.button [ HE.onClick \_ -> action, HP.class_ (HH.ClassName "transport-btn") ]
    [ HH.text label ]
