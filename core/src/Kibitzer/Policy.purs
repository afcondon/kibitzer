-- | How a player plays. Policies consult the player's own `Knowledge` —
-- | built by the same inference engine as the watcher's, just from a
-- | richer observation stream. The engine is dogfooded twice over: a
-- | player accuses exactly when their own fold of `learn` has determined
-- | the envelope, and (with movement on) walks toward rooms their own
-- | notebook still has questions about.
module Kibitzer.Policy
  ( Policy
  , randomLegalPolicy
  , randomSuggestion
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card(..), Room, allRooms, nonEmptyRooms, nonEmptySuspects, nonEmptyWeapons)
import Kibitzer.Knowledge (Knowledge, envelopeIn, envelopeOut, solutionIfKnown)
import Kibitzer.Rng (Seed, pick)
import Kibitzer.Suggestion (Solution, Suggestion)

-- | `suggest`'s first argument is the room the player has just entered
-- | (movement games force the room slot); `Nothing` means the room is a
-- | free choice (classic mode). `chooseDestination` receives the current
-- | room and must return a different one.
type Policy =
  { suggest :: Maybe Room -> Knowledge -> Seed -> Tuple Suggestion Seed
  , chooseShown :: Suggestion -> NonEmptyArray Card -> Seed -> Tuple Card Seed
  , chooseDestination :: Knowledge -> Room -> Seed -> Tuple Room Seed
  , accuse :: Knowledge -> Maybe Solution
  }

-- | Suggest uniformly at random (which may probe with cards the player
-- | holds — realistic, and useful noise for the watcher demo), show a
-- | uniformly chosen refuting card, walk purposefully (see
-- | `purposefulDestination`), and accuse the moment the player's own
-- | knowledge determines the solution.
randomLegalPolicy :: Policy
randomLegalPolicy =
  { suggest: \forcedRoom _ seed -> case forcedRoom of
      Nothing -> randomSuggestion seed
      Just room ->
        let
          Tuple suspect seed1 = pick nonEmptySuspects seed
          Tuple weapon seed2 = pick nonEmptyWeapons seed1
        in
          Tuple { suspect, weapon, room } seed2
  , chooseShown: \_ refuters seed -> pick refuters seed
  , chooseDestination: purposefulDestination
  , accuse: solutionIfKnown
  }

randomSuggestion :: Seed -> Tuple Suggestion Seed
randomSuggestion seed0 =
  let
    Tuple suspect seed1 = pick nonEmptySuspects seed0
    Tuple weapon seed2 = pick nonEmptyWeapons seed1
    Tuple room seed3 = pick nonEmptyRooms seed2
  in
    Tuple { suspect, weapon, room } seed3

-- | Where to walk, in order of preference:
-- | 1. the room known to be in the envelope (suggesting there aims every
-- |    refutation at the suspect and weapon slots);
-- | 2. uniformly among rooms whose envelope status is still undetermined;
-- | 3. uniformly among all other rooms.
-- | Always excludes the current room — the departure obligation.
purposefulDestination :: Knowledge -> Room -> Seed -> Tuple Room Seed
purposefulDestination knowledge current seed =
  case Array.findMap knownEnvelopeRoom (Set.toUnfoldable (envelopeIn knowledge)) of
    Just room | room /= current -> Tuple room seed
    _ -> case NEA.fromArray undetermined of
      Just candidates -> pick candidates seed
      Nothing -> case NEA.fromArray elsewhere of
        Just candidates -> pick candidates seed
        -- unreachable: there are always eight rooms other than `current`
        Nothing -> Tuple current seed
  where
  knownEnvelopeRoom = case _ of
    RoomCard r -> Just r
    _ -> Nothing

  elsewhere = Array.filter (_ /= current) allRooms

  undetermined = Array.filter
    ( \r ->
        not (Set.member (RoomCard r) (envelopeIn knowledge))
          && not (Set.member (RoomCard r) (envelopeOut knowledge))
    )
    elsewhere
