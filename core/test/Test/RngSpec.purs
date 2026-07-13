module Test.RngSpec (runRngTests) where

import Prelude

import Data.Array as Array
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Rng (mkSeed, seedToInt, shuffle, step, uniform)
import Test.QuickCheck (quickCheck)

runRngTests :: Effect Unit
runRngTests = do
  log "Rng: mkSeed lands in the generator's state space"
  quickCheck \n ->
    let s = seedToInt (mkSeed n)
    in s >= 1 && s < 2147483647

  log "Rng: step stays in the state space"
  quickCheck \n ->
    let Tuple v _ = step (mkSeed n)
    in v >= 1 && v < 2147483647

  log "Rng: uniform n lands in [0, n)"
  quickCheck \n bound ->
    let
      upper = 1 + bound `mod` 100
      Tuple v _ = uniform upper (mkSeed n)
    in
      v >= 0 && v < upper

  log "Rng: shuffle is deterministic in the seed"
  quickCheck \n (xs :: Array Int) ->
    fst (shuffle xs (mkSeed n)) == fst (shuffle xs (mkSeed n))

  log "Rng: shuffle is a permutation"
  quickCheck \n (xs :: Array Int) ->
    Array.sort (fst (shuffle xs (mkSeed n))) == Array.sort xs
