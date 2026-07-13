-- | The theorems, checked over random games:
-- |
-- |  1. Soundness — every fact any perspective ever infers is true of the
-- |     actual hidden deal, at every prefix of the log. This is the claim
-- |     the whole demo rests on: the watcher's notebook never lies.
-- |  2. Monotonicity — knowledge only grows along the log.
-- |  3. Player ⊇ watcher — public inference is a lower bound on every
-- |     player's private knowledge, at every prefix.
-- |  4. Fixpoint — saturate is idempotent; games end in a correct
-- |     accusation and the turn count matches the turn events.
module Test.PropSpec (runPropTests) where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (Card)
import Kibitzer.Event (Event(..), EventId(..))
import Kibitzer.Game (Result, simulate)
import Kibitzer.Infer (knowledgeTimeline, saturate)
import Kibitzer.Knowledge (Disjunction(..), Knowledge, consistent, disjunctions, envelopeIn, envelopeOut, facts, holdsOf, lacksOf)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (PlayerId, allPlayers, defaultPlayerCount, mkPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Suggestion (suggestionCards)
import Test.QuickCheck (quickCheck')

type GameCase =
  { result :: Result
  , hands :: Map PlayerId (Set Card)
  , players :: Array PlayerId
  }

runGame :: Int -> Int -> Boolean -> GameCase
runGame seedInt countInt movement =
  let
    count = fromMaybe defaultPlayerCount (mkPlayerCount (3 + countInt `mod` 4))
    result = simulate
      { playerCount: count
      , seed: mkSeed seedInt
      , policy: randomLegalPolicy
      , maxTurns: 1200
      , movement
      }
    hands = case Array.head result.log of
      Just (GameDealt d) -> d.hands
      _ -> Map.empty
  in
    { result, hands, players: allPlayers count }

perspectives :: GameCase -> Array Perspective
perspectives gc = Array.cons Watcher (map PlayerView gc.players)

timeline :: GameCase -> Perspective -> Array Knowledge
timeline gc perspective =
  knowledgeTimeline gc.result.playerCount perspective gc.result.log

handOf :: GameCase -> PlayerId -> Set Card
handOf gc p = fromMaybe Set.empty (Map.lookup p gc.hands)

-- | A snapshot never contradicts the hidden deal.
sound :: GameCase -> Knowledge -> Boolean
sound gc knowledge =
  Array.all (\p -> Set.subset (holdsOf knowledge p) (handOf gc p)) gc.players
    && Array.all (\p -> Set.isEmpty (Set.intersection (lacksOf knowledge p) (handOf gc p))) gc.players
    && Set.subset (envelopeIn knowledge) solutionCards
    && Set.isEmpty (Set.intersection (envelopeOut knowledge) solutionCards)
    && Array.all disjunctionSatisfied (disjunctions knowledge)
  where
  solutionCards = suggestionCards gc.result.solution

  disjunctionSatisfied (Disjunction d) =
    d.resolved || not (Set.isEmpty (Set.intersection d.candidates (handOf gc d.player)))

-- | Every premise a fact cites was already on the feed — the derivation
-- | DAG is well-founded (and therefore acyclic) at every snapshot.
wellFoundedProvenance :: Knowledge -> Boolean
wellFoundedProvenance knowledge =
  Array.all
    (\f -> Array.all (_ < f.id) f.justification.premises)
    (facts knowledge)

-- | Everything definite in `smaller` is definite in `larger`.
subsumedBy :: Array PlayerId -> Knowledge -> Knowledge -> Boolean
subsumedBy players smaller larger =
  Array.all (\p -> Set.subset (holdsOf smaller p) (holdsOf larger p)) players
    && Array.all (\p -> Set.subset (lacksOf smaller p) (lacksOf larger p)) players
    && Set.subset (envelopeIn smaller) (envelopeIn larger)
    && Set.subset (envelopeOut smaller) (envelopeOut larger)

consecutivePairs :: forall a. Array a -> Array (Tuple a a)
consecutivePairs xs = Array.zip xs (Array.drop 1 xs)

runPropTests :: Effect Unit
runPropTests = do
  -- Every theorem runs over both modes: `moves` is a generated Boolean.
  log "Prop: soundness — no perspective ever infers a false fact"
  quickCheck' 25 \seedInt countInt moves ->
    let
      gc = runGame seedInt countInt moves
    in
      Array.all
        ( \perspective ->
            Array.all
              (\k -> sound gc k && consistent k && wellFoundedProvenance k)
              (timeline gc perspective)
        )
        (perspectives gc)

  log "Prop: monotonicity — knowledge only grows along the log"
  quickCheck' 25 \seedInt countInt moves ->
    let
      gc = runGame seedInt countInt moves
    in
      Array.all
        ( \perspective ->
            Array.all (\(Tuple before after) -> subsumedBy gc.players before after)
              (consecutivePairs (timeline gc perspective))
        )
        (perspectives gc)

  log "Prop: the watcher never knows more than any player"
  quickCheck' 25 \seedInt countInt moves ->
    let
      gc = runGame seedInt countInt moves
      watcherLine = timeline gc Watcher
    in
      Array.all
        ( \p ->
            Array.all (\(Tuple w pl) -> subsumedBy gc.players w pl)
              (Array.zip watcherLine (timeline gc (PlayerView p)))
        )
        gc.players

  log "Prop: fixpoint and termination — saturate idempotent, games end correctly"
  quickCheck' 25 \seedInt countInt moves ->
    let
      gc = runGame seedInt countInt moves
      finals = map (\perspective -> Array.last (timeline gc perspective)) (perspectives gc)
      -- classic: one suggestion or accusation per counted turn;
      -- movement: one move or accusation per counted turn
      countsTurn = case _ of
        SuggestionMade _ -> not moves
        Moved _ -> moves
        AccusationMade _ -> true
        _ -> false
      turnEvents = Array.filter countsTurn gc.result.log
    in
      isJust gc.result.winner
        && gc.result.turns == Array.length turnEvents
        && Array.all
          ( case _ of
              Just k -> saturate (EventId 0) k == k
              Nothing -> false
          )
          finals
