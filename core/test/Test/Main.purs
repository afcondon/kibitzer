module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)
import Test.BoardSpec (runBoardTests)
import Test.CardsSpec (runCardsTests)
import Test.DealSpec (runDealTests)
import Test.GameSpec (runGameTests)
import Test.KnowledgeSpec (runKnowledgeTests)
import Test.PropSpec (runPropTests)
import Test.RngSpec (runRngTests)
import Test.WatcherSpec (runWatcherTests)

main :: Effect Unit
main = do
  runCardsTests
  runRngTests
  runDealTests
  runBoardTests
  runKnowledgeTests
  runGameTests
  runWatcherTests
  runPropTests
  log "All kibitzer-core tests passed."
