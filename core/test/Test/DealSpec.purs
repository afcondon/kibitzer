module Test.DealSpec (runDealTests) where

import Prelude

import Data.Foldable (sum)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (allCards)
import Kibitzer.Deal (deal)
import Kibitzer.Player (PlayerCount, handSizes, mkPlayerCount, totalDealt)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Suggestion (suggestionCards)
import Test.QuickCheck (quickCheck)

-- | Any Int names a legal table size; properties then range over all of 3..6.
arbitraryCount :: Int -> Maybe PlayerCount
arbitraryCount k = mkPlayerCount (3 + k `mod` 4)

runDealTests :: Effect Unit
runDealTests = do
  log "Deal: hands plus envelope partition the deck"
  quickCheck \n k -> case arbitraryCount k of
    Nothing -> false
    Just count ->
      let
        Tuple setup _ = deal count (mkSeed n)
        held = Set.unions (Map.values setup.hands)
        envelope = suggestionCards setup.solution
      in
        Set.union held envelope == Set.fromFoldable allCards
          && Set.isEmpty (Set.intersection held envelope)
          && sum (map Set.size (Map.values setup.hands)) == totalDealt

  log "Deal: hand sizes follow the round-robin split"
  quickCheck \n k -> case arbitraryCount k of
    Nothing -> false
    Just count ->
      let
        Tuple setup _ = deal count (mkSeed n)
      in
        map Set.size setup.hands == handSizes count

  log "Deal: deterministic in the seed"
  quickCheck \n k -> case arbitraryCount k of
    Nothing -> false
    Just count ->
      fst (deal count (mkSeed n)) == fst (deal count (mkSeed n))
