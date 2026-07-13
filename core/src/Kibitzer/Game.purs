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
-- | Two modes. Classic (`movement: false`): no board, no dice — any
-- | player may suggest any triple on their turn. Movement
-- | (`movement: true`): the real-rules constraint that you suggest only
-- | the room you are in — each turn you either accuse (from anywhere),
-- | or roll two dice and travel; arriving in a room triggers a suggestion
-- | there the same turn. See `Kibitzer.Board` for the geometry and the
-- | stated simplifications.
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
import Kibitzer.Board (Position(..), distance, rollTwoDice, startPositions)
import Kibitzer.Cards (Room(..))
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
  , movement :: Boolean
  }

type Result =
  { log :: Log
  , playerCount :: PlayerCount
  , solution :: Solution
  , winner :: Maybe PlayerId
  , turns :: Int
  , movement :: Boolean
  }

type SimState =
  { log :: Log
  , knowledge :: Map PlayerId Knowledge
  , positions :: Map PlayerId Position
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
      , positions: startPositions config.playerCount
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
    , movement: config.movement
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
        -- Accusation needs no room — a mid-journey epiphany is never wasted.
        Just accusation ->
          let
            correct = accusation == setup.solution
            accused = emit (AccusationMade { by: st.current, accusation, correct }) st
          in
            if correct then accused { winner = Just st.current }
            else accused { eliminated = Set.insert st.current accused.eliminated }
        Nothing
          | config.movement -> moveTurn setup mind st
          | otherwise ->
              let
                Tuple suggestion seed' = policy.suggest Nothing mind st.seed
                suggested = emit
                  (SuggestionMade { by: st.current, suggestion })
                  (st { seed = seed' })
              in
                resolveSuggestion setup st.current suggestion suggested

  -- Roll two dice and travel. `InRoom` is a departure obligation (see
  -- Kibitzer.Board); arriving triggers a suggestion in the same turn.
  -- The turn-start knowledge is still current at arrival because ObsMoved
  -- teaches nothing.
  moveTurn :: Setup -> Knowledge -> SimState -> SimState
  moveTurn setup mind st =
    let
      Tuple roll seed1 = rollTwoDice st.seed
      here = fromMaybe (InRoom Kitchen) (Map.lookup st.current st.positions)
    in
      case here of
        InRoom current ->
          let
            Tuple destination seed2 = policy.chooseDestination mind current seed1
            steps = distance current destination
            st' = st { seed = seed2 }
          in
            if roll >= steps then arrive setup mind destination roll st'
            else travel roll (EnRoute { from: current, to: destination, remaining: steps - roll }) st'
        EnRoute { from, to, remaining } ->
          let
            st' = st { seed = seed1 }
          in
            if roll >= remaining then arrive setup mind to roll st'
            else travel roll (EnRoute { from, to, remaining: remaining - roll }) st'
    where
    travel roll position st' =
      emit (Moved { player: st'.current, roll, position })
        (st' { positions = Map.insert st'.current position st'.positions })

    arrive setup' mind' room roll st' =
      let
        landed = emit (Moved { player: st'.current, roll, position: InRoom room })
          (st' { positions = Map.insert st'.current (InRoom room) st'.positions })
        Tuple suggestion seed' = policy.suggest (Just room) mind' landed.seed
        suggested = emit
          (SuggestionMade { by: landed.current, suggestion })
          (landed { seed = seed' })
      in
        resolveSuggestion setup' landed.current suggestion suggested

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
