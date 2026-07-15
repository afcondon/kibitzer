-- | Geometry for the cascade view: where every notebook cell, column
-- | header, event token, and sparkline bar sits in one fixed SVG viewBox.
-- | Pure arithmetic — the scene builders and the animation code both read
-- | from here, so the grid and the flying marks can never disagree.
module Kibitzer.Frontend.Cascade.Layout
  ( GridLayout(..)
  , svgWidth
  , svgHeight
  , gridTop
  , rowHeight
  , labelRight
  , rowIndex
  , rowY
  , columnX
  , envelopeColumn
  , claimCell
  , railAnchor
  , stripTop
  , stripHeight
  , stripSlot
  ) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Maybe (fromMaybe)
import Kibitzer.Cards (Card, allCards)
import Kibitzer.Knowledge (Claim(..))
import Kibitzer.Player (PlayerCount, PlayerId(..), playerCountToInt)

-- | The grid pane's three arrangements of the same marks: the notebook
-- | table, the derivation skyline (feed order × depth), and the radial
-- | DAG (depth as orbits). Every mark has a home in each; the morph
-- | animates between any pair.
data GridLayout = TableView | SkylineView | RadialView

derive instance Eq GridLayout

svgWidth :: Number
svgWidth = 760.0

svgHeight :: Number
svgHeight = 700.0

-- | Below the column headers and the event rail.
gridTop :: Number
gridTop = 64.0

rowHeight :: Number
rowHeight = 24.0

-- | Vertical breathing room between suspects / weapons / rooms.
categoryGap :: Number
categoryGap = 14.0

-- | Row labels are right-aligned against this edge.
labelRight :: Number
labelRight = 148.0

columnWidth :: Number
columnWidth = 56.0

firstColumnX :: Number
firstColumnX = 170.0

-- | Extra separation before the envelope column.
envelopeGap :: Number
envelopeGap = 18.0

-- | A card's row in the notebook — `allCards` order is the display order.
rowIndex :: Card -> Int
rowIndex c = fromMaybe 0 (Array.elemIndex c allCards)

-- | Row centre y, with a gap opening at each category boundary
-- | (6 suspects, 6 weapons, 9 rooms).
rowY :: Int -> Number
rowY row = gridTop + rowHeight * toNumber row + rowHeight / 2.0 + categoryGap * gaps
  where
  gaps
    | row >= 12 = 2.0
    | row >= 6 = 1.0
    | otherwise = 0.0

-- | Column centre x for player seats 0..n-1; the envelope column follows
-- | after a gap.
columnX :: PlayerCount -> Int -> Number
columnX count j
  | j >= playerCountToInt count =
      firstColumnX + columnWidth * toNumber j + envelopeGap + columnWidth / 2.0
  | otherwise = firstColumnX + columnWidth * toNumber j + columnWidth / 2.0

envelopeColumn :: PlayerCount -> Int
envelopeColumn = playerCountToInt

-- | The notebook cell a claim lands in.
claimCell :: PlayerCount -> Claim -> { x :: Number, y :: Number }
claimCell count = case _ of
  Holds (PlayerId p) c -> { x: columnX count p, y: rowY (rowIndex c) }
  Lacks (PlayerId p) c -> { x: columnX count p, y: rowY (rowIndex c) }
  InEnvelope c -> { x: columnX count (envelopeColumn count), y: rowY (rowIndex c) }
  NotInEnvelope c -> { x: columnX count (envelopeColumn count), y: rowY (rowIndex c) }

-- | Where the current event token sits — and where fresh facts fly from.
railAnchor :: { x :: Number, y :: Number }
railAnchor = { x: 24.0, y: 30.0 }

stripTop :: Number
stripTop = svgHeight - 46.0

stripHeight :: Number
stripHeight = 34.0

-- | Horizontal slot for timeline position i of n in the sparkline strip.
stripSlot :: Int -> Int -> { x :: Number, w :: Number }
stripSlot n i =
  let
    inner = svgWidth - 48.0
    w = inner / toNumber (max 1 n)
  in
    { x: 24.0 + w * toNumber i, w: max 1.0 (w - 1.0) }
