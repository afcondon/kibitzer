module Test.BoardSpec (runBoardTests) where

import Prelude

import Data.Array as Array
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.Tuple (Tuple(..), fst)
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Board (Position(..), distance, roomCoords, rollTwoDice, startPositions)
import Kibitzer.Cards (allRooms)
import Kibitzer.Player (mkPlayerCount)
import Kibitzer.Rng (mkSeed)
import Test.Assert (assert, assertEqual)
import Test.QuickCheck (quickCheck)

runBoardTests :: Effect Unit
runBoardTests = do
  log "Board: room coordinates tile the 3×3 grid exactly"
  let coords = map (\r -> let { x, y } = roomCoords r in Tuple x y) allRooms
  assertEqual { actual: Set.size (Set.fromFoldable coords), expected: 9 }
  assert (Array.all (\(Tuple x y) -> x >= 0 && x <= 2 && y >= 0 && y <= 2) coords)

  log "Board: distance is symmetric, zero iff equal, at least 5 otherwise"
  assert $ Array.all identity do
    r1 <- allRooms
    r2 <- allRooms
    pure
      ( distance r1 r2 == distance r2 r1
          && (distance r1 r2 == 0) == (r1 == r2)
          && (r1 == r2 || distance r1 r2 >= 5)
      )
  assert (Array.all (\r1 -> Array.all (\r2 -> distance r1 r2 <= 14) allRooms) allRooms)

  log "Board: start positions are distinct rooms for every table size"
  assert $ Array.all identity do
    n <- [ 3, 4, 5, 6 ]
    case mkPlayerCount n of
      Nothing -> pure false
      Just count ->
        let
          positions = Map.values (startPositions count)
          rooms = Array.mapMaybe
            ( case _ of
                InRoom r -> Just r
                EnRoute _ -> Nothing
            )
            (Array.fromFoldable positions)
        in
          pure (Array.length rooms == n && Set.size (Set.fromFoldable rooms) == n)

  log "Board: two dice land in [2, 12]"
  quickCheck \n ->
    let
      roll = fst (rollTwoDice (mkSeed n))
    in
      roll >= 2 && roll <= 12
