-- | Geometry and physics for the radial DAG — the derivation skyline
-- | bent into orbits. Depth becomes radius: observations on the
-- | outermost ring, derivations collapsing inward, and the envelope
-- | certainties at the bullseye — the argument literally closes in on
-- | the truth. Angle is feed order (the whole game sweeps clockwise
-- | from twelve o'clock), which makes the skyline ⇄ radial morph read
-- | as the x-axis curling into a circle.
-- |
-- | The physics is the packs' orbit trick, N rings instead of one: a
-- | filtered radial force per ring holds each fact at its depth, link
-- | forces along premise edges let conclusions settle at the angular
-- | position of their premises, and collision keeps the rings legible.
-- | Positions are read live each frame (`positionMap`); the analytic
-- | position doubles as the spawn point, so the sim starts near its
-- | own equilibrium.
module Kibitzer.Frontend.Cascade.Radial
  ( RadialRow
  , RadialNode
  , RingGuide
  , centre
  , ringGuides
  , analyticPos
  , templateNode
  , linksFor
  , positionMap
  , setupFor
  ) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Nullable (null)
import Data.Number (cos, pi, sin)
import Data.Tuple (Tuple(..))
import Hylograph.ForceEngine.Setup (Setup, collide, dynamic, link, positionX, positionY, radial, setup, static, withDistance, withFilter, withRadius, withStrength, withX, withY)
import Hylograph.ForceEngine.Simulation (SimulationNode)
import Kibitzer.Cascade (CascadeEdge)
import Kibitzer.Knowledge (Claim(..), Fact, FactId(..))

type RadialRow = (ring :: Number, ax :: Number, ay :: Number)

type RadialNode = SimulationNode RadialRow

centre :: { x :: Number, y :: Number }
centre = { x: 380.0, y: 350.0 }

outerRadius :: Number
outerRadius = 268.0

-- | Where the three `InEnvelope` certainties come to rest, whatever
-- | their derivation depth — the point of the whole argument.
bullseyeRadius :: Number
bullseyeRadius = 26.0

-- | The deepest ordinary ring stays clear of the bullseye.
innerFloor :: Number
innerFloor = 78.0

ringGap :: Int -> Number
ringGap maxDepth = min 88.0 ((outerRadius - innerFloor) / toNumber (max 1 maxDepth))

depthRing :: Int -> Int -> Number
depthRing maxDepth d = outerRadius - toNumber d * ringGap maxDepth

ringOf :: Map FactId Int -> Int -> Fact -> Number
ringOf depths maxDepth f = case f.claim of
  InEnvelope _ -> bullseyeRadius
  _ -> depthRing maxDepth (fromMaybe 0 (Map.lookup f.id depths))

-- | Feed order as angle, twelve o'clock start, clockwise — time sweeps
-- | around the dial. Stable across scrubbing because the denominator is
-- | the finished game's fact count.
angleOf :: Int -> Fact -> Number
angleOf total f =
  let
    FactId n = f.id
  in
    2.0 * pi * (toNumber n + 0.5) / toNumber (max 1 total) - pi / 2.0

analyticPos :: Map FactId Int -> Int -> Int -> Fact -> { x :: Number, y :: Number }
analyticPos depths maxDepth total f =
  let
    r = ringOf depths maxDepth f
    a = angleOf total f
  in
    { x: centre.x + r * cos a, y: centre.y + r * sin a }

type RingGuide = { r :: Number, label :: String, bullseye :: Boolean }

-- | When deep games pack the rings tight, labelling every ring stacks
-- | captions into an unreadable pile — label only every kth.
ringGuides :: Int -> Array RingGuide
ringGuides maxDepth =
  Array.cons
    { r: bullseyeRadius, label: "the envelope", bullseye: true }
    ( Array.range 0 maxDepth <#> \d ->
        { r: depthRing maxDepth d
        , label:
            if d == 0 then "observed directly"
            else if d `mod` labelEvery == 0 then "derived, " <> show d <> " deep"
            else ""
        , bullseye: false
        }
    )
  where
  labelEvery = max 1 (Int.ceil (20.0 / ringGap maxDepth))

templateNode :: Map FactId Int -> Int -> Int -> Fact -> RadialNode
templateNode depths maxDepth total f =
  let
    p = analyticPos depths maxDepth total f
    FactId n = f.id
  in
    { id: n
    , ring: ringOf depths maxDepth f
    , ax: p.x
    , ay: p.y
    , x: p.x
    , y: p.y
    , vx: 0.0
    , vy: 0.0
    , fx: null
    , fy: null
    }

-- | Physics links: premise edges among the facts visible at a position.
-- | Facts are id-dense, so `Array.index visible` is lookup by id, and
-- | premises precede conclusions, so resolving the conclusion suffices.
-- | Links touching an `InEnvelope` fact are dropped — its premises would
-- | drag it off the bullseye, and the bullseye is the point. (The drawn
-- | provenance edges are independent of these; nothing disappears.)
linksFor :: Array Fact -> Array CascadeEdge -> Array { source :: Int, target :: Int }
linksFor visible edges = edges # Array.mapMaybe \e -> do
  let FactId from = e.from
  let FactId to = e.to
  fromFact <- Array.index visible from
  toFact <- Array.index visible to
  case fromFact.claim, toFact.claim of
    InEnvelope _, _ -> Nothing
    _, InEnvelope _ -> Nothing
    _, _ -> Just { source: from, target: to }

positionMap :: Array RadialNode -> Map Int { x :: Number, y :: Number }
positionMap = Map.fromFoldable <<< map \n -> Tuple n.id { x: n.x, y: n.y }

-- | One filtered radial force per ring (rings are per-game constants, so
-- | the setup never needs rebuilding — scrubbing only changes the node
-- | population), weak springs along the premise edges, collision for
-- | spacing. The radial forces own radius; the links bend angle locally.
-- | The anchor springs matter: radial forces don't constrain angle, so
-- | without them the linked web contracts tangentially and the whole
-- | argument slides into a clot. A whisper of pull toward each fact's
-- | chronological slot keeps time sweeping around the dial.
setupFor :: Int -> Setup RadialNode
setupFor maxDepth =
  setup "radial-dag"
    ( [ collide "separate" # withRadius (static 9.5)
      , link "premises"
          # withStrength (static 0.12)
          # withDistance (static (ringGap maxDepth))
      , positionX "toSlotX" # withX (dynamic _.ax) # withStrength (static 0.05)
      , positionY "toSlotY" # withY (dynamic _.ay) # withStrength (static 0.05)
      ]
        <> ringForces
    )
  where
  ringForces = ringGuides maxDepth <#> \g ->
    radial ("ring-" <> show g.r)
      # withRadius (static g.r)
      # withX (static centre.x)
      # withY (static centre.y)
      # withStrength (static 0.55)
      # withFilter (\n -> n.ring == g.r)
