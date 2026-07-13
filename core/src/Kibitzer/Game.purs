-- | The simulator: deal, then a clockwise turn loop until someone's
-- | knowledge determines the envelope and they accuse.
-- |
-- | Refutation follows the standard rule: query players clockwise from the
-- | suggester's left; each holder of none of the three cards passes
-- | publicly, and the *first* holder shows one card — privately, to the
-- | suggester alone — which ends the query. Players beyond the shower
-- | reveal nothing. That asymmetry between what happened and what was
-- | publicly seen is the entire subject of this project.
-- |
-- | Simplification, stated plainly: there is no board, no dice, and no
-- | movement — any player may suggest any triple on their turn.
module Kibitzer.Game
  ( Config
  , Result
  , simulate
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NEA
import Data.FunctorWithIndex (mapWithIndex)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Kibitzer.Deal (Setup, deal)
import Kibitzer.Event (Event(..), EventId(..), Log)
import Kibitzer.Infer (learn)
import Kibitzer.Knowledge (Knowledge, emptyKnowledge)
import Kibitzer.Observe (Perspective(..), observe)
import Kibitzer.Player (PlayerCount, PlayerId(..), allPlayers, nextPlayer, playerCountToInt, queriedAfter)
import Kibitzer.Policy (Policy)
import Kibitzer.Rng (Seed)
import Kibitzer.Suggestion (Solution, Suggestion, matches)

type Config =
  { playerCount :: PlayerCount
  , seed :: Seed
  , policy :: Policy
  , maxTurns :: Int
  }

type Result =
  { log :: Log
  , playerCount :: PlayerCount
  , solution :: Solution
  , winner :: Maybe PlayerId
  , turns :: Int
  }

type SimState =
  { log :: Log
  , knowledge :: Map PlayerId Knowledge
  , seed :: Seed
  , current :: PlayerId
  , turnsTaken :: Int
  , eliminated :: Set PlayerId
  , winner :: Maybe PlayerId
  }

simulate :: Config -> Result
simulate config =
  let
    Tuple setup seed1 = deal config.playerCount config.seed
    opening = GameDealt
      { players: config.playerCount
      , hands: setup.hands
      , solution: setup.solution
      }
    start = emit opening
      { log: []
      , knowledge: blankMinds
      , seed: seed1
      , current: PlayerId 0
      , turnsTaken: 0
      , eliminated: Set.empty
      , winner: Nothing
      }
    final = loop setup start
  in
    { log: final.log
    , playerCount: config.playerCount
    , solution: setup.solution
    , winner: final.winner
    , turns: final.turnsTaken
    }
  where
  count = config.playerCount
  policy = config.policy

  blankMinds :: Map PlayerId Knowledge
  blankMinds = Map.fromFoldable
    (map (\p -> Tuple p (emptyKnowledge count)) (allPlayers count))

  loop :: Setup -> SimState -> SimState
  loop setup st
    | isJust st.winner = st
    | st.turnsTaken >= config.maxTurns = st
    | Set.size st.eliminated == playerCountToInt count = st
    | Set.member st.current st.eliminated = loop setup (advance st)
    | otherwise = loop setup (advance (takeTurn setup st))

  advance :: SimState -> SimState
  advance st = st { current = nextPlayer count st.current, turnsTaken = st.turnsTaken + 1 }

  takeTurn :: Setup -> SimState -> SimState
  takeTurn setup st =
    let
      mind = fromMaybe (emptyKnowledge count) (Map.lookup st.current st.knowledge)
    in
      case policy.accuse mind of
        Just accusation ->
          let
            correct = accusation == setup.solution
            accused = emit (AccusationMade { by: st.current, accusation, correct }) st
          in
            if correct then accused { winner = Just st.current }
            else accused { eliminated = Set.insert st.current accused.eliminated }
        Nothing ->
          let
            Tuple suggestion seed' = policy.suggest mind st.seed
            suggested = emit
              (SuggestionMade { by: st.current, suggestion })
              (st { seed = seed' })
          in
            resolveSuggestion setup st.current suggestion suggested

  -- Query clockwise; stop at the first player able to refute.
  resolveSuggestion :: Setup -> PlayerId -> Suggestion -> SimState -> SimState
  resolveSuggestion setup suggester suggestion = go (queriedAfter count suggester)
    where
    go queried st = case Array.uncons queried of
      Nothing -> st -- nobody could refute
      Just { head: q, tail } ->
        let
          hand = fromMaybe Set.empty (Map.lookup q setup.hands)
          refuters = Set.toUnfoldable (matches suggestion hand)
        in
          case NEA.fromArray refuters of
            Nothing -> go tail (emit (Passed { player: q, suggestion }) st)
            Just cards ->
              let
                Tuple card seed' = policy.chooseShown suggestion cards st.seed
              in
                emit
                  (CardShown { by: q, to: suggester, card, suggestion })
                  (st { seed = seed' })

  -- Append an event and let every player witness it from their own
  -- perspective. (The watcher's fold is not run here; consumers replay
  -- the log through `Kibitzer.Infer` at whatever position they like.)
  emit :: Event -> SimState -> SimState
  emit event st =
    let
      eid = EventId (Array.length st.log)
      witness p mind = learn (Tuple eid (observe (PlayerView p) event)) mind
    in
      st
        { log = Array.snoc st.log event
        , knowledge = mapWithIndex witness st.knowledge
        }
