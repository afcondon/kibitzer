module Test.CardsSpec (runCardsTests) where

import Prelude

import Data.Array as Array
import Data.Set as Set
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (Category(..), allCards, allCategories, allRooms, allSuspects, allWeapons, cardCategory, cardsIn)
import Test.Assert (assert, assertEqual)

runCardsTests :: Effect Unit
runCardsTests = do
  log "Cards: deck shape"
  assertEqual { actual: Array.length allSuspects, expected: 6 }
  assertEqual { actual: Array.length allWeapons, expected: 6 }
  assertEqual { actual: Array.length allRooms, expected: 9 }
  assertEqual { actual: Array.length allCards, expected: 21 }

  log "Cards: no duplicates"
  assertEqual { actual: Set.size (Set.fromFoldable allCards), expected: 21 }

  log "Cards: categories partition the deck"
  assert (Set.fromFoldable allCards == Set.unions (map cardsIn allCategories))
  assertEqual { actual: Set.size (cardsIn Suspects), expected: 6 }
  assertEqual { actual: Set.size (cardsIn Weapons), expected: 6 }
  assertEqual { actual: Set.size (cardsIn Rooms), expected: 9 }

  log "Cards: every card belongs to the category that claims it"
  assert $ Array.all
    (\category -> Set.isEmpty (Set.filter (\c -> cardCategory c /= category) (cardsIn category)))
    allCategories
