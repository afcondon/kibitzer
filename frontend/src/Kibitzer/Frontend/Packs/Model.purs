-- | The possibility-pack model. One node per (location, card) pair —
-- | "card c could be at location L" — where a location is a player seat
-- | or the envelope. Every node's state is a pure function of a
-- | Knowledge snapshot, so scrubbing either direction is just
-- | re-derivation; nothing incremental to maintain.
-- |
-- | Geometry: the envelope at the centre, players in a ring around it,
-- | each pack held together by per-node anchor forces + collision.
-- | Candidates of unresolved "showed one of these" disjunctions are
-- | lifted onto an orbit around their pack by a filtered radial force.
module Kibitzer.Frontend.Packs.Model
  ( PackRow
  , PackNode
  , PossState(..)
  , PossInfo
  , centreX
  , centreY
  , bubbleRadius
  , orbitRadius
  , envelopeLoc
  , anchorFor
  , nodeId
  , cardAt
  , cardIndex
  , templateNode
  , allTemplateNodes
  , locationOf
  , possState
  , deriveStates
  , survivorIds
  , orbitSets
  , setupFor
  , categoryColour
  ) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Nullable (null)
import Data.Number (cos, pi, sin, sqrt)
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple.Nested ((/\))
import Hylograph.ForceEngine.Setup (Setup, collide, dynamic, positionX, positionY, radial, setup, static, withFilter, withRadius, withStrength, withX, withY)
import Hylograph.ForceEngine.Simulation (SimulationNode)
import Kibitzer.Cards (Card, allCards)
import Data.String as String
import Kibitzer.Describe (cardPhrase, describeFact, eventRef, playerName)
import Kibitzer.Knowledge (Claim(..), Disjunction(..), Knowledge, disjunctions, envelopeIn, envelopeOut, facts, holdsOf, lacksOf)
import Kibitzer.Player (PlayerCount, PlayerId(..), allPlayers, playerCountToInt)

type PackRow = (loc :: Int, card :: Int, ax :: Number, ay :: Number)

type PackNode = SimulationNode PackRow

-- | What a possibility knows about itself, judged from one snapshot.
data PossState
  = Open -- nothing known
  | Ghost -- this location ruled out; true location still unknown
  | Confirmed -- the card is here
  | Gone -- the card is known to be elsewhere

derive instance Eq PossState

type PossInfo = { state :: PossState, tip :: String }

centreX :: Number
centreX = 380.0

centreY :: Number
centreY = 320.0

ringRadius :: Number
ringRadius = 205.0

bubbleRadius :: Number
bubbleRadius = 8.0

-- | Wide enough that "showed one of these" candidates visibly leave the
-- | pack — the orbit is an accusation-in-waiting and should read as one.
orbitRadius :: Number
orbitRadius = 68.0

cardCount :: Int
cardCount = Array.length allCards

-- | The envelope is "one more player" — the last location index.
envelopeLoc :: PlayerCount -> Int
envelopeLoc = playerCountToInt

-- | Envelope at the centre; seats on the ring, seat A at twelve o'clock.
anchorFor :: PlayerCount -> Int -> { x :: Number, y :: Number }
anchorFor count loc
  | loc == envelopeLoc count = { x: centreX, y: centreY }
  | otherwise =
      let
        n = toNumber (playerCountToInt count)
        angle = 2.0 * pi * toNumber loc / n - pi / 2.0
      in
        { x: centreX + ringRadius * cos angle
        , y: centreY + ringRadius * sin angle
        }

nodeId :: Int -> Int -> Int
nodeId loc card = loc * cardCount + card

cardAt :: Int -> Maybe Card
cardAt = Array.index allCards

cardIndex :: Card -> Int
cardIndex c = fromMaybe 0 (Array.elemIndex c allCards)

-- | A node at rest: spawned on a small golden-angle spiral around its
-- | anchor (deterministic — the whole app is a function of the seed).
templateNode :: PlayerCount -> Int -> Int -> PackNode
templateNode count loc card =
  let
    a = anchorFor count loc
    i = toNumber card
    r = 5.0 * sqrt i
    theta = i * 2.399963
  in
    { id: nodeId loc card
    , loc
    , card
    , ax: a.x
    , ay: a.y
    , x: a.x + r * cos theta
    , y: a.y + r * sin theta
    , vx: 0.0
    , vy: 0.0
    , fx: null
    , fy: null
    }

allTemplateNodes :: PlayerCount -> Array PackNode
allTemplateNodes count = do
  loc <- Array.range 0 (envelopeLoc count)
  card <- Array.range 0 (cardCount - 1)
  pure (templateNode count loc card)

-- | Where a card certainly is, if anywhere: a seat, or the envelope.
locationOf :: PlayerCount -> Knowledge -> Card -> Maybe Int
locationOf count knowledge c
  | Set.member c (envelopeIn knowledge) = Just (envelopeLoc count)
  | otherwise =
      Array.findMap
        ( \p@(PlayerId i) ->
            if Set.member c (holdsOf knowledge p) then Just i else Nothing
        )
        (allPlayers count)

possState :: PlayerCount -> Knowledge -> Int -> Card -> PossState
possState count knowledge loc c = case locationOf count knowledge c of
  Just there
    | there == loc -> Confirmed
    | otherwise -> Gone
  Nothing
    | ruledOutHere -> Ghost
    | otherwise -> Open
  where
  ruledOutHere
    | loc == envelopeLoc count = Set.member c (envelopeOut knowledge)
    | otherwise = Set.member c (lacksOf knowledge (PlayerId loc))

-- | State + hover provenance for every possibility, once per position.
deriveStates :: PlayerCount -> Knowledge -> Map Int PossInfo
deriveStates count knowledge =
  Map.fromFoldable do
    loc <- Array.range 0 (envelopeLoc count)
    card <- Array.range 0 (cardCount - 1)
    c <- Array.fromFoldable (cardAt card)
    let state = possState count knowledge loc c
    pure (nodeId loc card /\ { state, tip: tipFor loc c state })
  where

  tipFor loc c = case _ of
    -- an orbiting candidate explains why it left the pack
    Open -> case orbitStory loc c of
      Just story -> story
      Nothing -> cardPhrase c <> " — nothing known for " <> seatName loc
    Ghost -> factTip (ruledOutClaim loc c)
    Confirmed -> factTip (confirmedClaim loc c)
    Gone -> ""
    where
    seatName l
      | l == envelopeLoc count = "the envelope"
      | otherwise = playerName (PlayerId l)

  -- "F showed one of these at E23 — the Knife is a candidate."
  orbitStory loc c
    | loc == envelopeLoc count = Nothing
    | otherwise =
        case
          Array.filter
            ( \(Disjunction d) ->
                not d.resolved && d.player == PlayerId loc && Set.member c d.candidates
            )
            (disjunctions knowledge)
          of
          [] -> Nothing
          ds -> Just
            ( playerName (PlayerId loc)
                <> " showed one of these at "
                <> String.joinWith ", " (map (\(Disjunction d) -> eventRef d.source) ds)
                <> " — "
                <> cardPhrase c
                <> " is a candidate."
            )

  ruledOutClaim loc c
    | loc == envelopeLoc count = NotInEnvelope c
    | otherwise = Lacks (PlayerId loc) c

  confirmedClaim loc c
    | loc == envelopeLoc count = InEnvelope c
    | otherwise = Holds (PlayerId loc) c

  factTip claim =
    case Array.find (\f -> f.claim == claim) (facts knowledge) of
      Just f -> describeFact f
      Nothing -> ""

-- | The node ids still alive at a snapshot (everything not Gone).
survivorIds :: PlayerCount -> Knowledge -> Set Int
survivorIds count knowledge =
  Set.fromFoldable do
    loc <- Array.range 0 (envelopeLoc count)
    card <- Array.range 0 (cardCount - 1)
    c <- Array.fromFoldable (cardAt card)
    case possState count knowledge loc c of
      Gone -> []
      _ -> pure (nodeId loc card)

-- | Per seat, the card indexes sitting in unresolved disjunctions —
-- | these orbit the pack.
orbitSets :: Knowledge -> Map Int (Set Int)
orbitSets knowledge =
  Array.foldl step Map.empty (disjunctions knowledge)
  where
  step acc (Disjunction d)
    | d.resolved = acc
    | otherwise =
        let
          PlayerId p = d.player
        in
          Map.insertWith Set.union p (Set.map cardIndex d.candidates) acc

-- | Anchor springs + collision, plus one filtered radial force per pack
-- | that currently has orbiting candidates. Membership changes rebuild
-- | the setup (`handle.updateSetup`) — the filters are pure closures.
setupFor :: PlayerCount -> Map Int (Set Int) -> Setup PackNode
setupFor count orbits =
  setup "packs"
    ( [ positionX "toAnchorX" # withX (dynamic _.ax) # withStrength (static anchorStrength)
      , positionY "toAnchorY" # withY (dynamic _.ay) # withStrength (static anchorStrength)
      , collide "separate" # withRadius (static (bubbleRadius + 1.6))
      ]
        <> orbitForces
    )
  where
  anchorStrength = 0.11
  orbitStrength = 0.5

  -- the anchor springs keep pulling orbiters inward, so the radial
  -- equilibrium sits at r·s/(s+k); overshoot the pull radius by the
  -- inverse factor and the bubbles settle exactly on the drawn guide
  orbitPullRadius = orbitRadius * (orbitStrength + anchorStrength) / orbitStrength

  orbitForces =
    Map.toUnfoldable orbits # Array.mapMaybe \(loc /\ cardIdxs) ->
      if Set.isEmpty cardIdxs then Nothing
      else
        let
          a = anchorFor count loc
        in
          Just
            ( radial ("orbit-" <> show loc)
                # withRadius (static orbitPullRadius)
                # withX (static a.x)
                # withY (static a.y)
                # withStrength (static orbitStrength)
                # withFilter (\n -> n.loc == loc && Set.member n.card cardIdxs)
            )

-- | Category hues — muted, light-theme; the envelope's three end-state
-- | cards are automatically one of each.
categoryColour :: Int -> String
categoryColour card
  | card < 6 = "#5f7fbf" -- suspects
  | card < 12 = "#c9973b" -- weapons
  | otherwise = "#69a284" -- rooms
