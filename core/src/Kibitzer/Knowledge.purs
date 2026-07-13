-- | What a perspective knows, and how it knows it.
-- |
-- | Knowledge is four monotone sets of claims (held / not held, per player;
-- | in / out of the envelope), a list of live disjunctions ("that player
-- | holds at least one of these cards"), and an append-only feed of facts,
-- | each carrying its provenance: the rule that derived it and the event
-- | that triggered the derivation. The feed is what makes the watcher's
-- | notebook explainable rather than magic.
module Kibitzer.Knowledge
  ( Claim(..)
  , Rule(..)
  , Justification
  , FactId(..)
  , Fact
  , Disjunction(..)
  , Knowledge(..)
  , emptyKnowledge
  , holdsOf
  , lacksOf
  , heldByAnyone
  , addFact
  , addDisjunction
  , facts
  , factCount
  , disjunctions
  , envelopeIn
  , envelopeOut
  , solutionIfKnown
  , consistent
  ) where

import Prelude

import Data.Array as Array
import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set (Set)
import Data.Set as Set
import Data.Show.Generic (genericShow)
import Data.Tuple.Nested (type (/\), (/\))
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
  | EnvelopeByElimination -- a card no player holds must be in the envelope
  | CategoryCount -- one envelope slot per category, counted both ways
  | EnvelopeExcludesHands -- an envelope card is in no hand

derive instance Eq Rule
derive instance Generic Rule _

instance Show Rule where
  show = genericShow

-- | `source` is the event whose processing derived the fact; `origin`, when
-- | present, is the earlier show-event whose disjunction finally resolved.
type Justification = { rule :: Rule, source :: EventId, origin :: Maybe EventId }

newtype FactId = FactId Int

derive instance Eq FactId
derive instance Ord FactId

instance Show FactId where
  show (FactId i) = "(FactId " <> show i <> ")"

type Fact = { id :: FactId, claim :: Claim, justification :: Justification }

-- | "That player holds at least one of these cards" — the public residue of
-- | a card being shown. Candidates only ever shrink; `resolved` flips once
-- | the player is known to hold one of them.
newtype Disjunction = Disjunction
  { player :: PlayerId
  , candidates :: Set Card
  , source :: EventId
  , resolved :: Boolean
  }

derive instance Eq Disjunction
derive instance Generic Disjunction _

instance Show Disjunction where
  show = genericShow

newtype Knowledge = Knowledge
  { playerCount :: PlayerCount
  , handSizes :: Map PlayerId Int
  , holds :: Map PlayerId (Set Card)
  , lacks :: Map PlayerId (Set Card)
  , envelopeIn :: Set Card
  , envelopeOut :: Set Card
  , disjunctions :: Array Disjunction
  , facts :: Array Fact
  }

derive instance Eq Knowledge
derive instance Generic Knowledge _

instance Show Knowledge where
  show = genericShow

-- | Knowing nothing — not even hand sizes, which arrive with the deal.
emptyKnowledge :: PlayerCount -> Knowledge
emptyKnowledge playerCount = Knowledge
  { playerCount
  , handSizes: Map.empty
  , holds: Map.empty
  , lacks: Map.empty
  , envelopeIn: Set.empty
  , envelopeOut: Set.empty
  , disjunctions: []
  , facts: []
  }

holdsOf :: Knowledge -> PlayerId -> Set Card
holdsOf (Knowledge k) p = fromMaybe Set.empty (Map.lookup p k.holds)

lacksOf :: Knowledge -> PlayerId -> Set Card
lacksOf (Knowledge k) p = fromMaybe Set.empty (Map.lookup p k.lacks)

heldByAnyone :: Knowledge -> Set Card
heldByAnyone (Knowledge k) = Set.unions (Map.values k.holds)

facts :: Knowledge -> Array Fact
facts (Knowledge k) = k.facts

factCount :: Knowledge -> Int
factCount (Knowledge k) = Array.length k.facts

disjunctions :: Knowledge -> Array Disjunction
disjunctions (Knowledge k) = k.disjunctions

envelopeIn :: Knowledge -> Set Card
envelopeIn (Knowledge k) = k.envelopeIn

envelopeOut :: Knowledge -> Set Card
envelopeOut (Knowledge k) = k.envelopeOut

-- | Record a claim, if it is news. The first justification wins; a claim
-- | rederivable six ways still appears in the feed exactly once.
addFact :: { claim :: Claim, justification :: Justification } -> Knowledge -> Knowledge
addFact { claim, justification } knowledge@(Knowledge k)
  | alreadyKnown claim knowledge = knowledge
  | otherwise =
      let
        fact = { id: FactId (Array.length k.facts), claim, justification }
        recorded = case claim of
          Holds p c -> k { holds = Map.insertWith Set.union p (Set.singleton c) k.holds }
          Lacks p c -> k { lacks = Map.insertWith Set.union p (Set.singleton c) k.lacks }
          InEnvelope c -> k { envelopeIn = Set.insert c k.envelopeIn }
          NotInEnvelope c -> k { envelopeOut = Set.insert c k.envelopeOut }
      in
        Knowledge (recorded { facts = Array.snoc k.facts fact })

alreadyKnown :: Claim -> Knowledge -> Boolean
alreadyKnown claim knowledge = case claim of
  Holds p c -> Set.member c (holdsOf knowledge p)
  Lacks p c -> Set.member c (lacksOf knowledge p)
  InEnvelope c -> Set.member c (envelopeIn knowledge)
  NotInEnvelope c -> Set.member c (envelopeOut knowledge)

addDisjunction :: Disjunction -> Knowledge -> Knowledge
addDisjunction d (Knowledge k) = Knowledge (k { disjunctions = Array.snoc k.disjunctions d })

-- | The full solution, once one card per category is known to be in the
-- | envelope. The three lookups are independent — hence `ado`.
solutionIfKnown :: Knowledge -> Maybe Solution
solutionIfKnown (Knowledge k) =
  let
    inEnvelope = Set.toUnfoldable k.envelopeIn :: Array Card
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
consistent knowledge@(Knowledge k) =
  Array.all noContradiction heldEntries
    && Set.isEmpty (Set.intersection k.envelopeIn k.envelopeOut)
    && Array.all liveDisjunction k.disjunctions
    && Array.all withinHandSize heldEntries
  where
  heldEntries :: Array (PlayerId /\ Set Card)
  heldEntries = Map.toUnfoldable k.holds

  noContradiction (p /\ held) = Set.isEmpty (Set.intersection held (lacksOf knowledge p))
  liveDisjunction (Disjunction d) = d.resolved || not (Set.isEmpty d.candidates)
  withinHandSize (p /\ held) = case Map.lookup p k.handSizes of
    Nothing -> true
    Just size -> Set.size held <= size
