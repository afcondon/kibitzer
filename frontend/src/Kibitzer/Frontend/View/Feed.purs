-- | The derivation feed: every fact the watcher knows, newest first, each
-- | with its provenance. Facts born of the current event are highlighted —
-- | this is where "three passes = nine facts" becomes visible.
module Kibitzer.Frontend.View.Feed (feedPane) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Kibitzer.Describe (describeClaim, eventRef, ruleName)
import Kibitzer.Event (EventId(..))
import Kibitzer.Frontend.Types (Game, currentKnowledge)
import Kibitzer.Knowledge (Fact, facts)

feedPane :: forall w a. Game -> Int -> HH.HTML w a
feedPane game position =
  HH.section [ HP.class_ (HH.ClassName "feed-pane") ]
    [ HH.h2_ [ HH.text "How the watcher knows" ]
    , if Array.null allFacts then
        HH.p [ HP.class_ (HH.ClassName "pane-note") ] [ HH.text "Nothing yet. Facts will appear as the game unfolds." ]
      else
        HH.ol [ HP.class_ (HH.ClassName "feed") ]
          (map (factLine currentEventId) (Array.reverse allFacts))
    ]
  where
  allFacts = facts (currentKnowledge game position)
  currentEventId = EventId (position - 1)

factLine :: forall w a. EventId -> Fact -> HH.HTML w a
factLine currentEventId fact =
  HH.li
    [ HP.classes
        ( map HH.ClassName
            (if fact.justification.source == currentEventId then [ "fact", "fresh" ] else [ "fact" ])
        )
    ]
    [ HH.span [ HP.class_ (HH.ClassName "fact-source") ]
        [ HH.text (eventRef fact.justification.source) ]
    , HH.span [ HP.class_ (HH.ClassName "fact-rule") ]
        [ HH.text (ruleName fact.justification.rule) ]
    , HH.span [ HP.class_ (HH.ClassName "fact-claim") ]
        [ HH.text (describeClaim fact.claim) ]
    , case fact.justification.origin of
        Just origin ->
          HH.span [ HP.class_ (HH.ClassName "fact-origin") ]
            [ HH.text ("resolves " <> eventRef origin) ]
        Nothing -> HH.text ""
    ]
