-- | The transport: play controls, scrubber, and position — global
-- | chrome, living in the header. The event prose that used to ride
-- | along here now streams in the terminal column.
module Kibitzer.Frontend.View.Timeline (transportBar) where

import Prelude

import Data.Int as Int
import Data.Maybe (fromMaybe)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Kibitzer.Frontend.Types (Action(..), Game, maxPosition)

transportBar :: forall w. Game -> Int -> Boolean -> HH.HTML w Action
transportBar game position playing =
  HH.div [ HP.class_ (HH.ClassName "transport-bar") ]
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
    , HH.span [ HP.class_ (HH.ClassName "position") ]
        [ HH.text (positionLabel <> " / E" <> show (maxPosition game - 1)) ]
    ]
  where
  positionLabel = if position == 0 then "—" else "E" <> show (position - 1)

button :: forall w. String -> Action -> HH.HTML w Action
button label action =
  HH.button [ HE.onClick \_ -> action, HP.class_ (HH.ClassName "transport-btn") ]
    [ HH.text label ]
