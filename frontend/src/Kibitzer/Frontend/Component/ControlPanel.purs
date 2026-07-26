-- | The table-shape control: player count. Re-deals immediately with the
-- | committed seed, so this panel carries no local state at all — it
-- | mirrors its input and raises intents. (The seed lives in the floating
-- | transport as `SeedControl`; the board variant is gone — the demo runs
-- | board-off, so there is nothing to toggle.)
module Kibitzer.Frontend.Component.ControlPanel
  ( Input
  , Output(..)
  , Slot
  , component
  ) where

import Prelude

import Data.Const (Const)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

type Input = { players :: Int }

data Output = PlayersChanged Int

type Slot = H.Slot (Const Void) Output Unit

data Action
  = Receive Input
  | SetPlayers String

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
  SetPlayers s -> case Int.fromString s of
    Just n -> H.raise (PlayersChanged n)
    Nothing -> pure unit

render :: forall m. Input -> H.ComponentHTML Action () m
render st =
  HH.div [ HP.class_ (HH.ClassName "controls") ]
    [ HH.label_ [ HH.text "Players" ]
    , HH.select [ HE.onValueChange SetPlayers ]
        ( map
            ( \n -> HH.option
                [ HP.value (show n), HP.selected (n == st.players) ]
                [ HH.text (show n) ]
            )
            [ 3, 4, 5, 6 ]
        )
    ]
