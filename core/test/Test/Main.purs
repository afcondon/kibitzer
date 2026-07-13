module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)
import Test.CardsSpec (runCardsTests)
import Test.DealSpec (runDealTests)
import Test.RngSpec (runRngTests)

main :: Effect Unit
main = do
  runCardsTests
  runRngTests
  runDealTests
  log "All kibitzer-core tests passed."
