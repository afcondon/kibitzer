-- | What a perspective knows, and how it knows it.
-- |
-- | Since the jtms-port: the fact feed, hash-consing, and proof terms live
-- | in `baskerville-core` (the library kibitzer's engine was extracted into), and
-- | this module is the domain facade over it. The `Claim`/`Rule`/
-- | `Justification`/`Fact` shapes the rest of kibitzer consumes are
-- | unchanged; conversions happen at this module's boundary. Kibitzer's
-- | residue — the lattice state that refines *between* facts — is the
-- | disjunction store plus hand sizes.
-- |
-- | A note the port surfaced: kibitzer asserts no bare axioms. Every
-- | direct observation lands under a named rule (`OwnHand`, `SawCard`,
-- | `PassImpliesLacks`) so the feed can say how it knows; the kernel's
-- | `Axiom` constructor goes unused here.
module Kibitzer.Knowledge
  ( Claim(..)
  , Rule(..)
  , Justification
  , Fact
  , Disjunction(..)
  , Residue
  , Knowledge(..)
  , emptyKnowledge
  , playerCountOf
  , handSizesOf
  , withHandSizes
  , holdsOf
  , lacksOf
  , heldByAnyone
  , heldEntries
  , addFact
  , addDisjunction
  , factIdFor
  , facts
  , factCount
  , disjunctions
  , envelopeIn
  , envelopeOut
  , solutionIfKnown
  , consistent
  , toWhy
  , fromWhy
  , module ReExport
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl)
import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set (Set)
import Data.Set as Set
import Data.Show.Generic (genericShow)
import Data.Tuple.Nested (type (/\), (/\))
import Baskerville.Kernel (FactId(..), KB, Why(..)) as ReExport
import Baskerville.Kernel (FactId, KB, Why(..), emptyKB, knownClaims, residue, withResidue)
import Baskerville.Kernel as JK
import Kibitzer.Cards (Card(..), Room, Suspect, Weapon)
import Kibitzer.Event (EventId)
import Kibitzer.Player (PlayerCount, PlayerId)
import Kibitzer.Suggestion (Solution)

data Claim
  = Holds PlayerId Card
  | Lacks PlayerId Card
  | InEnvelope Card
  | NotInEnvelope Card

derive instance Eq Claim
derive instance Ord Claim
derive instance Generic Claim _

instance Show Claim where
  show = genericShow

-- | Every way a fact can come to be known, named so the UI can say so.
data Rule
  = OwnHand -- a player's dealt cards (private)
  | SawCard -- a card personally shown to or by a player (private)
  | PassImpliesLacks -- a pass means none of the three suggested cards
  | SingletonDisjunction -- a shown-card disjunction narrowed to one candidate
  | UniqueOwner -- a held card is nowhere else: not in other hands, not in the envelope
  | HandComplete -- a full hand excludes every other card
  | LastCandidateHand -- a dealt card only one player can still hold
  | DisjunctionCapacity -- free hand slots fully committed to disjoint disjunctions
  | DisjunctionPigeonhole -- distinct showers sharing a candidate pool exhaust it
  | EnvelopeByElimination -- a card no player holds must be in the envelope
  | CategoryCount -- one envelope slot per category, counted both ways
  | EnvelopeExcludesHands -- an envelope card is in no hand

derive instance Eq Rule
derive instance Generic Rule _

instance Show Rule where
  show = genericShow

-- | The shape the rest of kibitzer reads; converted to the kernel's `Why`
-- | at this module's boundary (`origins` ↔ `anchors`).
type Justification =
  { rule :: Rule
  , source :: EventId
  , origins :: Array EventId
  , premises :: Array FactId
  }

type Fact = { id :: FactId, claim :: Claim, justification :: Justification }

toWhy :: Justification -> Why Rule EventId
toWhy j = ByRule { rule: j.rule, source: j.source, premises: j.premises, anchors: j.origins }

fromWhy :: Why Rule EventId -> Justification
fromWhy = case _ of
  ByRule d -> { rule: d.rule, source: d.source, origins: d.anchors, premises: d.premises }
  -- Unreachable in kibitzer: every fact is asserted under a named rule.
  Axiom source -> { rule: OwnHand, source, origins: [], premises: [] }

-- | "That player holds at least one of these cards" — the public residue of
-- | a card being shown. Candidates only ever shrink; `resolved` flips once
-- | the player is known to hold one of them. `initial` keeps the candidates
-- | as born, so a resolution can name the facts that killed the other two.
newtype Disjunction = Disjunction
  { player :: PlayerId
  , candidates :: Set Card
  , initial :: Set Card
  , source :: EventId
  , resolved :: Boolean
  }

derive instance Eq Disjunction
derive instance Generic Disjunction _

instance Show Disjunction where
  show = genericShow

-- | The non-claim lattice state: hand sizes arrive with the deal and stay
-- | fixed; disjunction candidates only shrink.
type Residue =
  { playerCount :: PlayerCount
  , handSizes :: Map PlayerId Int
  , disjunctions :: Array Disjunction
  }

newtype Knowledge = Knowledge (KB Residue Claim Rule EventId)

-- | Equality includes the kernel's rederivation record (`alsoWhy`) — the
-- | idempotence tests therefore also pin that saturation at a fixpoint
-- | discovers no new derivations, not merely no new facts.
derive newtype instance Eq Knowledge

-- | Knowing nothing — not even hand sizes, which arrive with the deal.
emptyKnowledge :: PlayerCount -> Knowledge
emptyKnowledge playerCount = Knowledge
  (emptyKB { playerCount, handSizes: Map.empty, disjunctions: [] })

playerCountOf :: Knowledge -> PlayerCount
playerCountOf (Knowledge kb) = (residue kb).playerCount

handSizesOf :: Knowledge -> Map PlayerId Int
handSizesOf (Knowledge kb) = (residue kb).handSizes

withHandSizes :: Map PlayerId Int -> Knowledge -> Knowledge
withHandSizes handSizes (Knowledge kb) =
  Knowledge (withResidue (_ { handSizes = handSizes }) kb)

-- | The four claim views are folds over the kernel's claim set. At
-- | kibitzer's scale (a few hundred claims) the scans are free; the
-- | incremental indexes the pre-port module kept by hand are gone.
holdsOf :: Knowledge -> PlayerId -> Set Card
holdsOf (Knowledge kb) p = knownClaims kb # foldl step Set.empty
  where
  step acc = case _ of
    Holds q c | q == p -> Set.insert c acc
    _ -> acc

lacksOf :: Knowledge -> PlayerId -> Set Card
lacksOf (Knowledge kb) p = knownClaims kb # foldl step Set.empty
  where
  step acc = case _ of
    Lacks q c | q == p -> Set.insert c acc
    _ -> acc

heldByAnyone :: Knowledge -> Set Card
heldByAnyone (Knowledge kb) = knownClaims kb # foldl step Set.empty
  where
  step acc = case _ of
    Holds _ c -> Set.insert c acc
    _ -> acc

-- | Players with known held cards, with those cards — `Map` order, exactly
-- | as the pre-port `holds` index iterated (the goldens care).
heldEntries :: Knowledge -> Array (PlayerId /\ Set Card)
heldEntries (Knowledge kb) = Map.toUnfoldable (knownClaims kb # foldl step Map.empty)
  where
  step acc = case _ of
    Holds q c -> Map.insertWith Set.union q (Set.singleton c) acc
    _ -> acc

envelopeIn :: Knowledge -> Set Card
envelopeIn (Knowledge kb) = knownClaims kb # foldl step Set.empty
  where
  step acc = case _ of
    InEnvelope c -> Set.insert c acc
    _ -> acc

envelopeOut :: Knowledge -> Set Card
envelopeOut (Knowledge kb) = knownClaims kb # foldl step Set.empty
  where
  step acc = case _ of
    NotInEnvelope c -> Set.insert c acc
    _ -> acc

-- | Record a claim, if it is news. First justification wins (the kernel
-- | remembers rederivations on the side).
addFact :: { claim :: Claim, justification :: Justification } -> Knowledge -> Knowledge
addFact { claim, justification } (Knowledge kb) =
  Knowledge (JK.addFact { claim, why: toWhy justification } kb)

addDisjunction :: Disjunction -> Knowledge -> Knowledge
addDisjunction d (Knowledge kb) =
  Knowledge (withResidue (\r -> r { disjunctions = Array.snoc r.disjunctions d }) kb)

factIdFor :: Claim -> Knowledge -> Maybe FactId
factIdFor claim (Knowledge kb) = JK.factIdFor claim kb

facts :: Knowledge -> Array Fact
facts (Knowledge kb) = JK.facts kb <#> \f ->
  { id: f.id, claim: f.claim, justification: fromWhy f.why }

factCount :: Knowledge -> Int
factCount (Knowledge kb) = JK.factCount kb

disjunctions :: Knowledge -> Array Disjunction
disjunctions (Knowledge kb) = (residue kb).disjunctions

-- | The full solution, once one card per category is known to be in the
-- | envelope. The three lookups are independent — hence `ado`.
solutionIfKnown :: Knowledge -> Maybe Solution
solutionIfKnown knowledge =
  let
    inEnvelope = Set.toUnfoldable (envelopeIn knowledge) :: Array Card
  in
    ado
      suspect <- Array.findMap justSuspect inEnvelope
      weapon <- Array.findMap justWeapon inEnvelope
      room <- Array.findMap justRoom inEnvelope
      in { suspect, weapon, room }
  where
  justSuspect :: Card -> Maybe Suspect
  justSuspect = case _ of
    SuspectCard s -> Just s
    _ -> Nothing

  justWeapon :: Card -> Maybe Weapon
  justWeapon = case _ of
    WeaponCard w -> Just w
    _ -> Nothing

  justRoom :: Card -> Maybe Room
  justRoom = case _ of
    RoomCard r -> Just r
    _ -> Nothing

-- | Internal sanity: no claim and its negation, no starved disjunction,
-- | no hand over its size. Soundness (claims true of the actual deal) is
-- | checked in the test suite, which alone can see the deal.
consistent :: Knowledge -> Boolean
consistent knowledge =
  Array.all noContradiction held
    && Set.isEmpty (Set.intersection (envelopeIn knowledge) (envelopeOut knowledge))
    && Array.all liveDisjunction (disjunctions knowledge)
    && Array.all withinHandSize held
  where
  held :: Array (PlayerId /\ Set Card)
  held = heldEntries knowledge

  noContradiction (p /\ cards) = Set.isEmpty (Set.intersection cards (lacksOf knowledge p))
  liveDisjunction (Disjunction d) = d.resolved || not (Set.isEmpty d.candidates)
  withinHandSize (p /\ cards) = case Map.lookup p (handSizesOf knowledge) of
    Nothing -> true
    Just size -> Set.size cards <= size
