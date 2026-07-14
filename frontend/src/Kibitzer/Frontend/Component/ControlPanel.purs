-- | The deal controls as a child component: seed, table size, board
-- | variant, and the Deal/Random buttons. The one bit of genuinely local
-- | state is the seed *draft* — text the user has typed but not yet
-- | committed. Everything committed lives with the parent and arrives as
-- | `Input`; the panel raises complete configurations, never fragments,
-- | so the parent needs no knowledge of the form's innards.
-- |
-- | This panel is the reference client for the widget-library
-- | ControlPanel requirement (componentization plan §2).
module Kibitzer.Frontend.Component.ControlPanel
  ( Input
  , Output(..)
  , Slot
  , component
  ) where

import Prelude

import Data.Const (Const)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

-- | The committed configuration, as the parent knows it.
type Input = { seed :: Int, players :: Int, board :: Boolean }

data Output
  = DealRequested { seed :: Int, players :: Int, board :: Boolean }
  | RandomRequested { players :: Int, board :: Boolean }

type Slot = H.Slot (Const Void) Output Unit

type State =
  { draft :: String -- seed text as typed, possibly uncommitted
  , committed :: Input
  }

data Action
  = Receive Input
  | SetDraft String
  | SetPlayers String
  | ToggleBoard Boolean
  | Deal
  | Random

component :: forall q m. H.Component q Input Output m
component = H.mkComponent
  { initialState: \input -> { draft: show input.seed, committed: input }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }

handleAction :: forall m. Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  -- a new committed seed (e.g. Random rolled one) replaces the draft;
  -- otherwise the user's typing survives parent re-renders
  Receive input -> H.modify_ \st ->
    { draft: if input.seed /= st.committed.seed then show input.seed else st.draft
    , committed: input
    }
  SetDraft s -> H.modify_ _ { draft = s }
  -- table-shape changes re-deal at once, carrying the draft seed
  SetPlayers s -> case Int.fromString s of
    Just n -> raiseDeal _ { players = n }
    Nothing -> pure unit
  ToggleBoard b -> raiseDeal _ { board = b }
  Deal -> raiseDeal identity
  Random -> do
    st <- H.get
    H.raise (RandomRequested { players: st.committed.players, board: st.committed.board })
  where
  raiseDeal adjust = do
    st <- H.get
    let
      seed = fromMaybe st.committed.seed (Int.fromString (String.trim st.draft))
      config = adjust { seed, players: st.committed.players, board: st.committed.board }
    H.raise (DealRequested config)

render :: forall m. State -> H.ComponentHTML Action () m
render st =
  HH.div [ HP.class_ (HH.ClassName "controls") ]
    [ HH.label_ [ HH.text "Seed" ]
    , HH.input
        [ HP.value st.draft
        , HP.type_ HP.InputText
        , HE.onValueInput SetDraft
        ]
    , HH.label_ [ HH.text "Players" ]
    , HH.select [ HE.onValueChange SetPlayers ]
        ( map
            ( \n -> HH.option
                [ HP.value (show n), HP.selected (n == st.committed.players) ]
                [ HH.text (show n) ]
            )
            [ 3, 4, 5, 6 ]
        )
    , HH.label [ HP.class_ (HH.ClassName "toggle") ]
        [ HH.input
            [ HP.type_ HP.InputCheckbox
            , HP.checked st.committed.board
            , HE.onChecked ToggleBoard
            ]
        , HH.text "Board"
        ]
    , HH.button [ HE.onClick \_ -> Deal ] [ HH.text "Deal" ]
    , HH.button [ HE.onClick \_ -> Random ] [ HH.text "Random" ]
    ]
