-- | The seed as global chrome: an input and a recycle button in the top
-- | nav, since every view is a view of one seeded game. The draft text
-- | is the only local state; Enter or leaving the field commits it, the
-- | recycle button asks the parent for a fresh roll (randomness is an
-- | effect, so it belongs to the store).
module Kibitzer.Frontend.Component.SeedControl
  ( Input
  , Output(..)
  , Slot
  , component
  ) where

import Prelude

import Data.Const (Const)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String as String
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Web.UIEvent.KeyboardEvent as KE

type Input = Int -- the committed seed

data Output
  = Committed Int
  | Rerolled

type Slot = H.Slot (Const Void) Output Unit

type State = { draft :: String, committed :: Int }

data Action
  = Receive Input
  | SetDraft String
  | Commit
  | KeyPressed KE.KeyboardEvent
  | Reroll

component :: forall q m. H.Component q Input Output m
component = H.mkComponent
  { initialState: \seed -> { draft: show seed, committed: seed }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , receive = Just <<< Receive
      }
  }

handleAction :: forall m. Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  -- a new committed seed (e.g. a reroll landed) replaces the draft;
  -- otherwise typing survives parent re-renders
  Receive seed -> H.modify_ \st ->
    { draft: if seed /= st.committed then show seed else st.draft
    , committed: seed
    }
  SetDraft s -> H.modify_ _ { draft = s }
  Commit -> do
    st <- H.get
    case Int.fromString (String.trim st.draft) of
      Just n -> H.raise (Committed n)
      Nothing -> H.modify_ _ { draft = show st.committed }
  KeyPressed e -> when (KE.key e == "Enter") (handleAction Commit)
  Reroll -> H.raise Rerolled

render :: forall m. State -> H.ComponentHTML Action () m
render st =
  HH.div [ HP.class_ (HH.ClassName "seed-control") ]
    [ HH.label_ [ HH.text "Seed" ]
    , HH.input
        [ HP.value st.draft
        , HP.type_ HP.InputText
        , HE.onValueInput SetDraft
        , HE.onValueChange \_ -> Commit
        , HE.onKeyDown KeyPressed
        ]
    , HH.button
        [ HE.onClick \_ -> Reroll
        , HP.title "Deal a random seed"
        , HP.class_ (HH.ClassName "reroll")
        ]
        [ HH.text "↻" ]
    ]
