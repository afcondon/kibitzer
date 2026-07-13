-- | Glyphs and small formatting helpers shared by the panes. The prose
-- | itself comes from `Kibitzer.Describe` in the core.
module Kibitzer.Frontend.Format
  ( categoryClass
  , glyphHolds
  , glyphLacks
  , glyphUnknown
  ) where

import Kibitzer.Cards (Card, Category(..), cardCategory)

categoryClass :: Card -> String
categoryClass card = case cardCategory card of
  Suspects -> "suspect"
  Weapons -> "weapon"
  Rooms -> "room"

glyphHolds :: String
glyphHolds = "✓"

glyphLacks :: String
glyphLacks = "✗"

glyphUnknown :: String
glyphUnknown = "·"
