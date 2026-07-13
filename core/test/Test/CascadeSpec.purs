-- | The cascade frames: shape, alignment, and DAG discipline over the
-- | seed-42 golden game.
module Test.CascadeSpec (runCascadeTests) where

import Prelude

import Data.Array as Array
import Data.Foldable (any)
import Data.Map as Map
import Data.Maybe (fromMaybe)
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cascade (cascadeTimeline)
import Kibitzer.Game (simulate)
import Kibitzer.Infer (knowledgeAt)
import Kibitzer.Knowledge (Rule(..), facts)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (defaultPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Test.Assert (assert, assertEqual)

runCascadeTests :: Effect Unit
runCascadeTests = do
  let
    result = simulate
      { playerCount: defaultPlayerCount
      , seed: mkSeed 42
      , policy: randomLegalPolicy
      , maxTurns: 200
      , movement: false
      }
    frames = cascadeTimeline defaultPlayerCount Watcher result.log
    final = knowledgeAt defaultPlayerCount Watcher (Array.length result.log) result.log

  log "Cascade: one frame per timeline position, aligned with the log"
  assertEqual { actual: Array.length frames, expected: Array.length result.log + 1 }

  log "Cascade: frame newFacts partition the final fact feed"
  do
    let reassembled = Array.concatMap _.newFacts frames
    assertEqual { actual: Array.length reassembled, expected: Array.length (facts final) }
    assertEqual
      { actual: Array.sortWith _.id reassembled # map _.id
      , expected: map _.id (facts final)
      }

  log "Cascade: every edge points forward (premise before conclusion)"
  assert
    ( Array.all (\fr -> Array.all (\e -> e.from < e.to) fr.edges) frames
    )

  log "Cascade: observation facts sit at depth 0; derived depths honour premises"
  assert
    ( frames # Array.all \fr ->
        fr.newFacts # Array.all \f ->
          let
            d = fromMaybe (-1) (Map.lookup f.id fr.depth)
          in
            case f.justification.rule of
              PassImpliesLacks -> d == 0
              OwnHand -> d == 0
              SawCard -> d == 0
              _ -> d >= 0
    )

  log "Cascade: newFacts arrive sorted by (depth, id)"
  assert
    ( frames # Array.all \fr ->
        let
          keys = map (\f -> fromMaybe 0 (Map.lookup f.id fr.depth) /\ f.id) fr.newFacts
        in
          keys == Array.sort keys
    )

  log "Cascade: the seed-42 game contains a genuine avalanche"
  do
    -- at least one frame where a same-frame derivation chain formed
    assert (frames # Array.any \fr -> any (_ >= 1) (Map.values fr.depth))
    -- and at least one frame with a burst of five or more facts
    assert (frames # Array.any \fr -> Array.length fr.newFacts >= 5)

  log "Cascade: a resolved disjunction's frame carries its edges"
  do
    -- find the frame where a SingletonDisjunction fact is born; it must
    -- cite at least one premise and its origins name the show-event
    let
      resolutionFrames = frames # Array.filter \fr ->
        fr.newFacts # Array.any (\f -> f.justification.rule == SingletonDisjunction)
    assert (not (Array.null resolutionFrames))
    assert
      ( resolutionFrames # Array.all \fr ->
          fr.newFacts
            # Array.filter (\f -> f.justification.rule == SingletonDisjunction)
            # Array.all \f ->
                not (Array.null f.justification.premises)
                  && not (Array.null f.justification.origins)
      )
