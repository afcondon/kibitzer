-- | Golden state of the watcher's notebook at the end of the seed-42 game:
-- | 70 facts, ten cards placed exactly, no card ever seen.
module Test.WatcherSpec (runWatcherTests) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (Card(..), Room(..), Suspect(..), Weapon(..))
import Kibitzer.Infer (knowledgeAt)
import Kibitzer.Knowledge (consistent, envelopeIn, envelopeOut, factCount, holdsOf, solutionIfKnown)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (PlayerId(..), defaultPlayerCount)
import Test.Assert (assert, assertEqual)
import Test.GameSpec (seed42)

runWatcherTests :: Effect Unit
runWatcherTests = do
  log "Watcher: seed-42 golden notebook"
  let
    result = seed42
    watcher = knowledgeAt defaultPlayerCount Watcher (Array.length result.log) result.log

  assertEqual { actual: factCount watcher, expected: 70 }
  assert (consistent watcher)

  -- The watcher placed these cards exactly, without seeing any of them.
  assert (Set.member (RoomCard BilliardRoom) (holdsOf watcher (PlayerId 1)))
  assert (Set.member (SuspectCard White) (holdsOf watcher (PlayerId 2)))
  assert (Set.member (WeaponCard Wrench) (holdsOf watcher (PlayerId 2)))
  assert (Set.member (SuspectCard Peacock) (holdsOf watcher (PlayerId 3)))
  assert (Set.member (RoomCard Library) (holdsOf watcher (PlayerId 0)))

  -- At this seed the watcher gets close but does not fully solve it:
  -- ten cards ruled out of the envelope, none yet ruled in.
  assertEqual { actual: Set.size (envelopeIn watcher), expected: 0 }
  assertEqual { actual: Set.size (envelopeOut watcher), expected: 10 }
  assertEqual { actual: solutionIfKnown watcher, expected: Nothing }
