-- | Invariants of the movement variant, checked over random games via
-- | `Kibitzer.Track` — the same position-replay the frontend map renders.
module Test.MovementSpec (runMovementTests) where

import Prelude

import Data.Array as Array
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Board (Position(..))
import Kibitzer.Event (Event(..), Log)
import Kibitzer.Game (Result, simulate)
import Kibitzer.Player (PlayerId, defaultPlayerCount, mkPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Track (positionsTimeline)
import Test.QuickCheck (quickCheck')

movementGame :: Int -> Int -> Result
movementGame seedInt countInt = simulate
  { playerCount: fromMaybe defaultPlayerCount (mkPlayerCount (3 + countInt `mod` 4))
  , seed: mkSeed seedInt
  , policy: randomLegalPolicy
  , maxTurns: 1200
  , movement: true
  }

runMovementTests :: Effect Unit
runMovementTests = do
  log "Movement: every suggestion is made from inside its room"
  quickCheck' 25 \seedInt countInt ->
    let
      result = movementGame seedInt countInt
      timeline = positionsTimeline result.playerCount result.log
      legal i = case _ of
        SuggestionMade { by, suggestion } ->
          -- timeline entry i is the state after events 0..i-1, which
          -- includes the arrival Moved immediately preceding this event
          (Map.lookup by =<< Array.index timeline i) == Just (InRoom suggestion.room)
        _ -> true
    in
      Array.all identity (Array.mapWithIndex legal result.log)

  log "Movement: every arrival is followed at once by that player's suggestion"
  quickCheck' 25 \seedInt countInt ->
    let
      result = movementGame seedInt countInt
      cadence i = case _ of
        Moved { player, position: InRoom _ } ->
          case Array.index result.log (i + 1) of
            Just (SuggestionMade { by }) -> by == player
            _ -> false
        _ -> true
    in
      Array.all identity (Array.mapWithIndex cadence result.log)

  log "Movement: rolls in [2,12], journeys progress strictly"
  quickCheck' 25 \seedInt countInt ->
    let
      result = movementGame seedInt countInt
      rollsOk = Array.all
        ( case _ of
            Moved { roll, position } ->
              roll >= 2 && roll <= 12 &&
                case position of
                  EnRoute { remaining } -> remaining >= 1
                  InRoom _ -> true
            _ -> true
        )
        result.log
      journeysOk = Array.all playerProgresses (movesByPlayer result.log)
    in
      rollsOk && journeysOk

movesByPlayer :: Log -> Array (Array Position)
movesByPlayer log =
  map
    ( \(Tuple _ moves) -> moves )
    ( Map.toUnfoldable
        ( Array.foldl
            ( \acc -> case _ of
                Moved { player, position } ->
                  Map.insertWith (<>) player [ position ] acc
                _ -> acc
            )
            (Map.empty :: Map.Map PlayerId (Array Position))
            log
        )
    )

-- | Along one player's consecutive moves, a continued journey to the same
-- | destination must have strictly fewer steps remaining.
playerProgresses :: Array Position -> Boolean
playerProgresses moves =
  Array.all identity
    ( Array.zipWith
        ( \a b -> case a, b of
            EnRoute r1, EnRoute r2 | r1.to == r2.to -> r2.remaining < r1.remaining
            _, _ -> true
        )
        moves
        (Array.drop 1 moves)
    )
