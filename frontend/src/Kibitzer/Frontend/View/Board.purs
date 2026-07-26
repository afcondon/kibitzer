-- | The left pane: ground truth. The actual hands and the envelope —
-- | everything the watcher is NOT allowed to use. Showing it is the point:
-- | the viewer can verify with their own eyes that the notebook on the
-- | right never lies. A slim strip; the seat that is acting this turn
-- | lights up, tying the ground truth to the event stepper.
-- |
-- | (The stylised movement board is gone: the demo runs board-off, where
-- | the watcher's signal is at its strongest — the point is not that it
-- | beats the players but that it extracts *any* signal from pure
-- | metadata, and increasingly much as the table grows.)
module Kibitzer.Frontend.View.Board (groundTruthPane) where

import Prelude

import Data.Array as Array
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Kibitzer.Cards (Card(..), displayName)
import Kibitzer.Describe (playerName)
import Kibitzer.Event (Event(..))
import Kibitzer.Frontend.Format (categoryClass)
import Kibitzer.Frontend.Types (Game, currentEvent)
import Kibitzer.Player (PlayerId, allPlayers)
import Kibitzer.Suggestion (Suggestion)

groundTruthPane :: forall w a. Game -> Int -> HH.HTML w a
groundTruthPane game position =
  HH.section [ HP.class_ (HH.ClassName "board-pane") ]
    [ HH.h2_ [ HH.text "The table" ]
    , HH.p [ HP.class_ (HH.ClassName "pane-note") ]
        [ HH.text "Ground truth — the watcher cannot see any of this." ]
    , envelopeView game
    , HH.div [ HP.class_ (HH.ClassName "seats") ]
        (map (seatView game position) (allPlayers game.result.playerCount))
    ]

envelopeView :: forall w a. Game -> HH.HTML w a
envelopeView game =
  HH.div [ HP.class_ (HH.ClassName "envelope") ]
    [ HH.span [ HP.class_ (HH.ClassName "envelope-label") ] [ HH.text "The envelope" ]
    , suggestionChips game.result.solution
    ]

seatView :: forall w a. Game -> Int -> PlayerId -> HH.HTML w a
seatView game position p =
  HH.div
    [ HP.classes (map HH.ClassName (Array.cons "seat" (seatStateClasses game position p))) ]
    [ HH.div [ HP.class_ (HH.ClassName "seat-name") ] [ HH.text (playerName p) ]
    , HH.div [ HP.class_ (HH.ClassName "hand") ] (map cardChip (handOf game p))
    ]

handOf :: Game -> PlayerId -> Array Card
handOf game p = case Array.head game.result.log of
  Just (GameDealt d) -> Set.toUnfoldable (fromMaybe Set.empty (Map.lookup p d.hands))
  _ -> []

seatStateClasses :: Game -> Int -> PlayerId -> Array String
seatStateClasses game position p = case currentEvent game position of
  Just (SuggestionMade { by }) | by == p -> [ "suggesting" ]
  Just (Passed { player }) | player == p -> [ "passing" ]
  Just (CardShown { by }) | by == p -> [ "showing" ]
  Just (CardShown { to }) | to == p -> [ "receiving" ]
  Just (AccusationMade { by }) | by == p -> [ "accusing" ]
  _ -> []

suggestionChips :: forall w a. Suggestion -> HH.HTML w a
suggestionChips { suspect, weapon, room } =
  HH.div [ HP.class_ (HH.ClassName "chips") ]
    [ chip "suspect" (displayName (SuspectCard suspect))
    , chip "weapon" (displayName (WeaponCard weapon))
    , chip "room" (displayName (RoomCard room))
    ]

cardChip :: forall w a. Card -> HH.HTML w a
cardChip card = chip (categoryClass card) (displayName card)

chip :: forall w a. String -> String -> HH.HTML w a
chip cls label =
  HH.span [ HP.classes [ HH.ClassName "chip", HH.ClassName cls ] ] [ HH.text label ]
