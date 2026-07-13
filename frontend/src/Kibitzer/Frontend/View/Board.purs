-- | The left pane: ground truth. The actual hands, the envelope, and the
-- | event in progress — everything the watcher is NOT allowed to use.
-- | Showing it is the point: the viewer can verify with their own eyes
-- | that the notebook on the right never lies.
module Kibitzer.Frontend.View.Board (boardPane) where

import Prelude

import Data.Array as Array
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Kibitzer.Board (Position(..), roomCoords)
import Kibitzer.Cards (Card(..), Room, allRooms, displayName, roomName)
import Kibitzer.Describe (describeEvent, playerName)
import Kibitzer.Event (Event(..))
import Kibitzer.Frontend.Format (categoryClass)
import Kibitzer.Frontend.Types (Game, currentEvent)
import Kibitzer.Player (PlayerId, allPlayers)
import Kibitzer.Suggestion (Suggestion)

boardPane :: forall w a. Game -> Int -> HH.HTML w a
boardPane game position =
  HH.section [ HP.class_ (HH.ClassName "board-pane") ]
    ( [ HH.h2_ [ HH.text "The table" ]
      , HH.p [ HP.class_ (HH.ClassName "pane-note") ]
          [ HH.text "Ground truth — the watcher cannot see any of this." ]
      , envelopeView game
      ]
        <> (if game.result.movement then [ mapView game position ] else [])
        <>
          [ HH.div [ HP.class_ (HH.ClassName "seats") ]
              (map (seatView game position) (allPlayers game.result.playerCount))
          , stageView game position
          ]
    )

-- | The stylised board: the 3×3 room grid with lettered tokens. Room
-- | boxes come out in `allRooms` order, which is already row-major for
-- | `roomCoords`. Tokens are absolutely positioned from the same
-- | coordinates, at the room centre (or the journey midpoint when en
-- | route), nudged per seat so they never fully overlap.
mapView :: forall w a. Game -> Int -> HH.HTML w a
mapView game position =
  HH.div [ HP.class_ (HH.ClassName "map") ]
    (map roomBox allRooms <> Array.mapWithIndex token players)
  where
  players = allPlayers game.result.playerCount

  positionsNow = fromMaybe Map.empty (Array.index game.positions position)

  roomBox room =
    HH.div [ HP.class_ (HH.ClassName "map-room") ]
      [ HH.span_ [ HH.text (roomName room) ] ]

  token i p = case Map.lookup p positionsNow of
    Nothing -> HH.text ""
    Just pos ->
      let
        { x, y } = tokenTenths i pos
        enRouteBadge = case pos of
          EnRoute { remaining } ->
            [ HH.span [ HP.class_ (HH.ClassName "token-remaining") ]
                [ HH.text (show remaining) ]
            ]
          InRoom _ -> []
      in
        HH.div
          [ HP.classes
              ( map HH.ClassName
                  (if isEnRoute pos then [ "token", "en-route" ] else [ "token" ])
              )
          , HP.style ("left:" <> pct x <> ";top:" <> pct y)
          ]
          ([ HH.text (playerName p) ] <> enRouteBadge)

  isEnRoute = case _ of
    EnRoute _ -> true
    InRoom _ -> false

-- | Percent coordinates in tenths (all-Int arithmetic): room centres at
-- | 16.6/50.0/83.3%, plus a small per-seat nudge.
tokenTenths :: Int -> Position -> { x :: Int, y :: Int }
tokenTenths i pos = case pos of
  InRoom r -> nudge (centreTenths r)
  EnRoute { from, to } ->
    let
      a = centreTenths from
      b = centreTenths to
    in
      nudge { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
  where
  nudge { x, y } =
    let
      offsets = [ { x: -45, y: -45 }, { x: 45, y: -45 }, { x: -45, y: 45 }, { x: 45, y: 45 }, { x: 0, y: -60 }, { x: 0, y: 60 } ]
      o = fromMaybe { x: 0, y: 0 } (Array.index offsets i)
    in
      { x: x + o.x, y: y + o.y }

centreTenths :: Room -> { x :: Int, y :: Int }
centreTenths room =
  let
    { x, y } = roomCoords room
  in
    { x: (x * 1000 + 500) / 3, y: (y * 1000 + 500) / 3 }

pct :: Int -> String
pct tenths = show (tenths / 10) <> "." <> show (tenths `mod` 10) <> "%"

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
  Just (Moved { player }) | player == p -> [ "moving" ]
  Just (SuggestionMade { by }) | by == p -> [ "suggesting" ]
  Just (Passed { player }) | player == p -> [ "passing" ]
  Just (CardShown { by }) | by == p -> [ "showing" ]
  Just (CardShown { to }) | to == p -> [ "receiving" ]
  Just (AccusationMade { by }) | by == p -> [ "accusing" ]
  _ -> []

-- | The centre stage: what is happening right now, in ground-truth prose.
stageView :: forall w a. Game -> Int -> HH.HTML w a
stageView game position =
  HH.div [ HP.class_ (HH.ClassName "stage") ] case currentEvent game position of
    Nothing ->
      [ HH.p [ HP.class_ (HH.ClassName "stage-caption") ]
          [ HH.text "Cards have been dealt. Press play." ]
      ]
    Just event ->
      stageChips event
        <> [ HH.p [ HP.class_ (HH.ClassName "stage-caption") ] [ HH.text (describeEvent event) ] ]

stageChips :: forall w a. Event -> Array (HH.HTML w a)
stageChips = case _ of
  SuggestionMade { suggestion } -> [ suggestionChips suggestion ]
  Passed { suggestion } -> [ suggestionChips suggestion ]
  CardShown { suggestion, card } -> [ suggestionChips suggestion, shownCard card ]
  AccusationMade { accusation } -> [ suggestionChips accusation ]
  Moved _ -> []
  GameDealt _ -> []

shownCard :: forall w a. Card -> HH.HTML w a
shownCard card =
  HH.div [ HP.class_ (HH.ClassName "shown-card") ]
    [ HH.span [ HP.class_ (HH.ClassName "shown-label") ] [ HH.text "shown, face down to the room:" ]
    , cardChip card
    ]

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
