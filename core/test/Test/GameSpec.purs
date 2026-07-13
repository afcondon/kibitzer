-- | Golden transcript for seed 42: the exact game the README and the
-- | frontend cross-check against. If simulation or the Rng change, these
-- | numbers move — deliberately loudly.
module Test.GameSpec (runGameTests, seed42, seed42Moves) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Board (Position(..))
import Kibitzer.Cards (Card(..), Room(..), Suspect(..), Weapon(..))
import Kibitzer.Game (Result, simulate)
import Kibitzer.Event (Event(..))
import Kibitzer.Player (PlayerId(..), defaultPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Test.Assert (assert, assertEqual)

seed42 :: Result
seed42 = simulate
  { playerCount: defaultPlayerCount
  , seed: mkSeed 42
  , policy: randomLegalPolicy
  , maxTurns: 200
  , movement: false
  }

runGameTests :: Effect Unit
runGameTests = do
  log "Game: seed-42 golden transcript"
  let result = seed42
  assertEqual { actual: Array.length result.log, expected: 96 }
  assertEqual { actual: result.winner, expected: Just (PlayerId 3) }
  assertEqual { actual: result.turns, expected: 40 }
  assertEqual
    { actual: result.solution
    , expected: { suspect: Mustard, weapon: Revolver, room: Study }
    }

  log "Game: seed-42 opening moves, verbatim"
  let
    opening = { suspect: Plum, weapon: Candlestick, room: BilliardRoom }
  assertEqual
    { actual: Array.index result.log 1
    , expected: Just (SuggestionMade { by: PlayerId 0, suggestion: opening })
    }
  assertEqual
    { actual: Array.index result.log 2
    , expected: Just
        ( CardShown
            { by: PlayerId 1
            , to: PlayerId 0
            , card: RoomCard BilliardRoom
            , suggestion: opening
            }
        )
    }

  log "Game: the log ends with the winning accusation"
  assertEqual
    { actual: Array.last result.log
    , expected: Just
        ( AccusationMade
            { by: PlayerId 3
            , accusation: result.solution
            , correct: true
            }
        )
    }

  log "Game: deterministic in the seed"
  assert (seed42.log == result.log)

  log "Game: seed-42 movement golden"
  let moved = seed42Moves
  -- the deal precedes any policy or dice, so the envelope is the same
  -- game as classic seed 42 — only the path to it differs
  assertEqual { actual: moved.solution, expected: result.solution }
  assertEqual { actual: Array.length moved.log, expected: 35 }
  assertEqual { actual: moved.winner, expected: Just (PlayerId 1) }
  assertEqual { actual: moved.turns, expected: 14 }
  -- E1 is A's first move: rolls 7, reaches the adjacent Ballroom (5 steps)
  assertEqual
    { actual: Array.index moved.log 1
    , expected: Just
        ( Moved
            { player: PlayerId 0
            , roll: 7
            , position: InRoom Ballroom
            }
        )
    }
  assertEqual
    { actual: Array.last moved.log
    , expected: Just
        ( AccusationMade
            { by: PlayerId 1
            , accusation: moved.solution
            , correct: true
            }
        )
    }

seed42Moves :: Result
seed42Moves = simulate
  { playerCount: defaultPlayerCount
  , seed: mkSeed 42
  , policy: randomLegalPolicy
  , maxTurns: 600
  , movement: true
  }
