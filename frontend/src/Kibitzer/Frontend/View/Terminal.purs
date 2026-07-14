-- | The middle column: the game's event stream as a scrolling terminal,
-- | newest line at the bottom, under the headline counter. This is the
-- | ground-truth transcript — the same prose the table's stage shows one
-- | line at a time.
module Kibitzer.Frontend.View.Terminal (terminalPane) where

import Prelude

import Data.Array as Array
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Kibitzer.Describe (describeEvent)
import Kibitzer.Event (Event)
import Kibitzer.Frontend.Types (Game, currentKnowledge)
import Kibitzer.Knowledge (factCount)

terminalPane :: forall w a. Game -> Int -> HH.HTML w a
terminalPane game position =
  HH.section [ HP.class_ (HH.ClassName "terminal-pane") ]
    [ counter
    , if position == 0 then
        HH.p [ HP.class_ (HH.ClassName "pane-note") ]
          [ HH.text "Nothing yet. Press play — every event lands here." ]
      else
        -- newest-first in the DOM; CSS column-reverse pins the view to
        -- the latest line with no scroll bookkeeping at all
        HH.ol [ HP.class_ (HH.ClassName "terminal") ]
          (Array.reverse (Array.mapWithIndex line (Array.take position game.result.log)))
    ]
  where
  counter =
    HH.div [ HP.class_ (HH.ClassName "counter") ]
      [ HH.div [ HP.class_ (HH.ClassName "stat") ]
          [ HH.span [ HP.class_ (HH.ClassName "stat-number") ] [ HH.text "0" ]
          , HH.span [ HP.class_ (HH.ClassName "stat-label") ] [ HH.text "cards seen" ]
          ]
      , HH.div [ HP.classes (map HH.ClassName [ "stat", "accent" ]) ]
          [ HH.span [ HP.class_ (HH.ClassName "stat-number") ]
              [ HH.text (show (factCount (currentKnowledge game position))) ]
          , HH.span [ HP.class_ (HH.ClassName "stat-label") ] [ HH.text "facts inferred" ]
          ]
      ]

  line :: Int -> Event -> HH.HTML w a
  line i event =
    HH.li
      [ HP.classes
          (map HH.ClassName (if i == position - 1 then [ "term-line", "latest" ] else [ "term-line" ]))
      ]
      [ HH.span [ HP.class_ (HH.ClassName "term-ref") ] [ HH.text ("E" <> show i) ]
      , HH.span_ [ HH.text (describeEvent event) ]
      ]
