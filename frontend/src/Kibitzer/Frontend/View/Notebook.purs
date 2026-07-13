-- | The star pane: the watcher's detective notebook. A row per card,
-- | a column per player plus the envelope; ✓ known held, ✗ known not
-- | held, · undetermined. A small ring marks cards that sit in a live
-- | disjunction — "that player showed one of these" — with the details
-- | in the cell's tooltip.
module Kibitzer.Frontend.View.Notebook (notebookPane) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.String as String
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Kibitzer.Cards (Card, Category, allCategories, cardsIn, displayName)
import Kibitzer.Describe (cardPhrase, describeSuggestion, eventRef, playerName)
import Kibitzer.Frontend.Format (categoryClass, glyphHolds, glyphLacks, glyphUnknown)
import Kibitzer.Frontend.Types (Game, currentKnowledge)
import Kibitzer.Knowledge (Disjunction(..), Knowledge, disjunctions, envelopeIn, envelopeOut, holdsOf, lacksOf, solutionIfKnown)
import Kibitzer.Player (PlayerId, allPlayers)

notebookPane :: forall w a. Game -> Int -> HH.HTML w a
notebookPane game position =
  HH.section [ HP.class_ (HH.ClassName "notebook-pane") ]
    [ HH.h2_ [ HH.text "The watcher's notebook" ]
    , HH.p [ HP.class_ (HH.ClassName "pane-note") ]
        [ HH.text "Inferred from public metadata only: who asked, who passed, who showed something." ]
    , notebookTable game knowledge
    , verdict knowledge
    ]
  where
  knowledge = currentKnowledge game position

notebookTable :: forall w a. Game -> Knowledge -> HH.HTML w a
notebookTable game knowledge =
  HH.table [ HP.class_ (HH.ClassName "notebook") ]
    (Array.cons headerRow (Array.concatMap categoryRows allCategories))
  where
  players = allPlayers game.result.playerCount

  headerRow = HH.tr_
    ( [ HH.th_ [] ]
        <> map (\p -> HH.th_ [ HH.text (playerName p) ]) players
        <> [ HH.th [ HP.class_ (HH.ClassName "env-col") ] [ HH.text "Env" ] ]
    )

  categoryRows :: Category -> Array (HH.HTML w a)
  categoryRows category =
    Array.mapWithIndex (\i card -> cardRow (i == 0) card) (Set.toUnfoldable (cardsIn category))

  cardRow :: Boolean -> Card -> HH.HTML w a
  cardRow categoryStart card =
    HH.tr
      [ HP.classes
          ( map HH.ClassName
              (if categoryStart then [ categoryClass card, "category-start" ] else [ categoryClass card ])
          )
      ]
      ( [ HH.td [ HP.class_ (HH.ClassName "card-label") ] [ HH.text (displayName card) ] ]
          <> map (playerCell card) players
          <> [ envelopeCell card ]
      )

  playerCell :: Card -> PlayerId -> HH.HTML w a
  playerCell card p =
    let
      inDisjunctions = liveDisjunctionsFor knowledge p card
      base
        | Set.member card (holdsOf knowledge p) = { cls: "holds", glyph: glyphHolds }
        | Set.member card (lacksOf knowledge p) = { cls: "lacks", glyph: glyphLacks }
        | otherwise = { cls: "unknown", glyph: glyphUnknown }
      badge = if Array.null inDisjunctions then [] else [ HH.ClassName "in-disjunction" ]
      tooltip =
        if Array.null inDisjunctions then []
        else [ HP.title (String.joinWith "\n" (map (describeDisjunction p) inDisjunctions)) ]
    in
      HH.td
        ([ HP.classes ([ HH.ClassName "cell", HH.ClassName base.cls ] <> badge) ] <> tooltip)
        [ HH.text base.glyph ]

  envelopeCell :: Card -> HH.HTML w a
  envelopeCell card =
    let
      state
        | Set.member card (envelopeIn knowledge) = { cls: "env-in", glyph: glyphHolds }
        | Set.member card (envelopeOut knowledge) = { cls: "lacks", glyph: glyphLacks }
        | otherwise = { cls: "unknown", glyph: glyphUnknown }
    in
      HH.td
        [ HP.classes [ HH.ClassName "cell", HH.ClassName "env-col", HH.ClassName state.cls ] ]
        [ HH.text state.glyph ]

liveDisjunctionsFor :: Knowledge -> PlayerId -> Card -> Array Disjunction
liveDisjunctionsFor knowledge p card =
  Array.filter
    ( \(Disjunction d) ->
        not d.resolved && d.player == p && Set.member card d.candidates
    )
    (disjunctions knowledge)

describeDisjunction :: PlayerId -> Disjunction -> String
describeDisjunction p (Disjunction d) =
  playerName p
    <> " showed one of: "
    <> String.joinWith ", " (map cardPhrase (Set.toUnfoldable d.candidates))
    <> " (at "
    <> eventRef d.source
    <> ")"

verdict :: forall w a. Knowledge -> HH.HTML w a
verdict knowledge = case solutionIfKnown knowledge of
  Just solution ->
    HH.p [ HP.class_ (HH.ClassName "verdict solved") ]
      [ HH.text ("The watcher has solved it: " <> describeSuggestion solution <> ".") ]
  Nothing ->
    HH.p [ HP.class_ (HH.ClassName "verdict") ]
      [ HH.text "The full solution is not yet determined." ]
