-- | The middle column: the game's event stream as a top-prepending
-- | stack — newest line at the top, older history pushed down beneath it,
-- | under the headline counter. This is the
-- | ground-truth transcript — the same prose the table's stage shows one
-- | line at a time. On the cross-referenced page each line is also a
-- | hover source and target: hovering it lights everything the event
-- | taught, and hovering a fact elsewhere lights the lines it came from.
module Kibitzer.Frontend.View.Terminal (terminalPane) where

import Prelude

import Data.Array as Array
import Data.Set (Set)
import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Kibitzer.Describe (describeEvent)
import Kibitzer.Event (Event)
import Kibitzer.Frontend.Types (Game, currentKnowledge)
import Kibitzer.Knowledge (factCount)

terminalPane
  :: forall w a
   . { onEnter :: Int -> a, onLeave :: a }
  -> Set Int -- event indexes implicated by the current hover
  -> Game
  -> Int
  -> HH.HTML w a
terminalPane hoverHandlers implicated game position =
  HH.section [ HP.class_ (HH.ClassName "terminal-pane") ]
    [ counter
    , if position == 0 then
        HH.p [ HP.class_ (HH.ClassName "pane-note") ]
          [ HH.text "Nothing yet. Press play — every event lands here." ]
      else
        -- newest-first in the DOM, laid out top-down (CSS `column`), so
        -- the latest line sits at the top and history stacks beneath it
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
          ( map HH.ClassName
              ( [ "term-line" ]
                  <> (if i == position - 1 then [ "latest" ] else [])
                  <> (if Set.member i implicated then [ "hl" ] else [])
              )
          )
      , HE.onMouseEnter \_ -> hoverHandlers.onEnter i
      , HE.onMouseLeave \_ -> hoverHandlers.onLeave
      ]
      [ HH.span [ HP.class_ (HH.ClassName "term-ref") ] [ HH.text ("E" <> show i) ]
      , HH.span_ [ HH.text (describeEvent event) ]
      ]
