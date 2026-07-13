-- | One unit test per deduction rule, on hand-fed observation streams.
module Test.KnowledgeSpec (runKnowledgeTests) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (Card(..), Room(..), Suspect(..), Weapon(..))
import Kibitzer.Event (EventId(..))
import Kibitzer.Infer (learn, saturate)
import Kibitzer.Knowledge (Claim(..), Disjunction(..), Knowledge, Rule(..), disjunctions, emptyKnowledge, envelopeOut, factCount, facts, holdsOf, lacksOf, solutionIfKnown)
import Kibitzer.Observe (Observation(..))
import Kibitzer.Player (PlayerId(..), allPlayers, defaultPlayerCount, handSizes)
import Kibitzer.Suggestion (Suggestion)
import Test.Assert (assert, assertEqual)

sugg :: Suspect -> Weapon -> Room -> Suggestion
sugg suspect weapon room = { suspect, weapon, room }

pass :: Int -> Suggestion -> Observation
pass i suggestion = ObsPassed { player: PlayerId i, suggestion }

feed :: Array Observation -> Knowledge
feed observations =
  foldl (flip learn) (emptyKnowledge defaultPlayerCount)
    (Array.mapWithIndex (\i o -> Tuple (EventId i) o) observations)

runKnowledgeTests :: Effect Unit
runKnowledgeTests = do
  log "Knowledge: a pass means lacking all three suggested cards"
  do
    let k = feed [ pass 1 (sugg White Wrench Kitchen) ]
    assert (Set.member (SuspectCard White) (lacksOf k (PlayerId 1)))
    assert (Set.member (WeaponCard Wrench) (lacksOf k (PlayerId 1)))
    assert (Set.member (RoomCard Kitchen) (lacksOf k (PlayerId 1)))
    assertEqual { actual: factCount k, expected: 3 }
    assert (Array.all (\f -> f.justification.rule == PassImpliesLacks) (facts k))

  log "Knowledge: a seen card is held — and is then nowhere else (unique owner)"
  do
    let
      k = feed
        [ ObsShowed
            { by: PlayerId 2
            , to: PlayerId 0
            , suggestion: sugg Plum Rope Study
            , card: Just (WeaponCard Rope)
            }
        ]
    assert (Set.member (WeaponCard Rope) (holdsOf k (PlayerId 2)))
    assert (Set.member (WeaponCard Rope) (envelopeOut k))
    assert (Set.member (WeaponCard Rope) (lacksOf k (PlayerId 0)))
    assert (Set.member (WeaponCard Rope) (lacksOf k (PlayerId 3)))

  log "Knowledge: a shown-card disjunction resolves once two candidates die"
  do
    let
      k = feed
        [ ObsShowed
            { by: PlayerId 1
            , to: PlayerId 0
            , suggestion: sugg Scarlett Rope Study
            , card: Nothing
            }
        , pass 1 (sugg Mustard Rope Kitchen)
        , pass 1 (sugg Plum Knife Study)
        ]
    assert (Set.member (SuspectCard Scarlett) (holdsOf k (PlayerId 1)))
    case Array.find (\f -> f.claim == Holds (PlayerId 1) (SuspectCard Scarlett)) (facts k) of
      Nothing -> assert false
      Just f -> do
        assertEqual { actual: f.justification.rule, expected: SingletonDisjunction }
        assertEqual { actual: f.justification.origin, expected: Just (EventId 0) }
        assertEqual { actual: f.justification.source, expected: EventId 2 }
    assert (Array.all (\(Disjunction d) -> d.resolved) (disjunctions k))

  log "Knowledge: a full hand excludes every other card"
  do
    let
      hand = Set.fromFoldable
        [ SuspectCard Scarlett
        , WeaponCard Rope
        , RoomCard Study
        , RoomCard Hall
        , RoomCard Lounge
        ]
      k = feed
        [ ObsDealt
            { players: defaultPlayerCount
            , handSizes: handSizes defaultPlayerCount
            , ownHand: Just { player: PlayerId 0, hand }
            }
        ]
    assertEqual { actual: Set.size (holdsOf k (PlayerId 0)), expected: 5 }
    assertEqual { actual: Set.size (lacksOf k (PlayerId 0)), expected: 16 }

  log "Knowledge: cards no one holds are the envelope, and categories close"
  do
    let
      everyonePasses = map
        (\(PlayerId i) -> pass i (sugg White Wrench Kitchen))
        (allPlayers defaultPlayerCount)
      k = feed everyonePasses
    assertEqual { actual: solutionIfKnown k, expected: Just (sugg White Wrench Kitchen) }
    assert (Array.any (\f -> f.justification.rule == EnvelopeByElimination) (facts k))
    -- CategoryCount: the envelope's siblings are excluded from it
    assert (Set.member (SuspectCard Scarlett) (envelopeOut k))
    assert (Set.member (WeaponCard Rope) (envelopeOut k))
    assert (Set.member (RoomCard Study) (envelopeOut k))

  log "Knowledge: a dealt card only one player can still hold is theirs"
  do
    let
      everyonePasses = map
        (\(PlayerId i) -> pass i (sugg White Wrench Kitchen))
        (allPlayers defaultPlayerCount)
      threePass = map (\i -> pass i (sugg Scarlett Knife Study)) [ 0, 1, 2 ]
      k = feed (everyonePasses <> threePass)
    assert (Set.member (SuspectCard Scarlett) (holdsOf k (PlayerId 3)))
    assert (Array.any (\f -> f.justification.rule == LastCandidateHand) (facts k))

  log "Knowledge: saturate is idempotent on saturated states"
  do
    let
      k = feed
        [ pass 1 (sugg White Wrench Kitchen)
        , ObsShowed
            { by: PlayerId 2
            , to: PlayerId 0
            , suggestion: sugg Plum Rope Study
            , card: Nothing
            }
        ]
    assert (saturate (EventId 99) k == k)
