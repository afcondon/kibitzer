-- | The transport as a child component: play controls, scrubber, and
-- | position readout — global chrome, living in the header. Stateless;
-- | everything it shows arrives as `Input`, every press leaves as
-- | `Output`. Step and jump buttons are just scrubs to computed
-- | positions (the parent clamps), so the whole surface is two intents.
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
  HH.div [ HP.class_ (HH.ClassName "transport-bar") ]
    [ HH.div [ HP.class_ (HH.ClassName "transport") ]
        [ button "⏮" (Scrubbed 0)
        , button "◀" (Scrubbed (position - 1))
        , button (if playing then "⏸" else "▶") PlayToggled
        , button "▶▶" (Scrubbed (position + 1))
        , button "⏭" (Scrubbed maxPos)
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

button :: forall m. String -> Output -> H.ComponentHTML Action () m
button label output =
  HH.button
    [ HE.onClick \_ -> Raise output, HP.class_ (HH.ClassName "transport-btn") ]
    [ HH.text label ]
