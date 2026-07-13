-- | Run a seeded game and print both sides of the split screen: the
-- | ground-truth transcript, then the watcher's notebook — everything a
-- | non-player deduced without ever seeing a card.
-- |
-- |   spago run -p kibitzer-example -- 42
module Example.Main where

import Prelude

import Data.Array as Array
import Data.Foldable (for_, traverse_)
import Data.Int as Int
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Monoid (power)
import Data.Set as Set
import Data.String as String
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cards (Card, allCards, displayName)
import Kibitzer.Describe (describeEvent, describeFact, describeSuggestion, playerName)
import Kibitzer.Event (Event(..))
import Kibitzer.Game (Result, simulate)
import Kibitzer.Infer (knowledgeAt)
import Kibitzer.Knowledge (Knowledge, envelopeIn, envelopeOut, facts, factCount, holdsOf, lacksOf, solutionIfKnown)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (PlayerCount, PlayerId, allPlayers, defaultPlayerCount)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Node.Process (argv)

main :: Effect Unit
main = do
  args <- argv
  let seedInt = fromMaybe 42 (Array.index args 2 >>= Int.fromString)
  run defaultPlayerCount seedInt

run :: PlayerCount -> Int -> Effect Unit
run count seedInt = do
  let
    result = simulate
      { playerCount: count
      , seed: mkSeed seedInt
      , policy: randomLegalPolicy
      , maxTurns: 200
      , movement: false
      }
  log ("kibitzer — seed " <> show seedInt <> "\n")

  log "— Ground truth (what the cameras saw) —"
  log ("The envelope: " <> describeSuggestion result.solution)
  printHands result
  log ""

  log "— Transcript —"
  for_ (Array.mapWithIndex Tuple result.log) \(Tuple i event) ->
    log ("E" <> show i <> "  " <> describeEvent event)
  log ""

  let watcher = knowledgeAt count Watcher (Array.length result.log) result.log

  log "— The watcher's notebook —"
  log (renderGrid count watcher)

  log "— Derivation feed (every fact, with its provenance) —"
  traverse_ (log <<< describeFact) (facts watcher)
  log ""

  log ("Cards seen by the watcher: 0 — Facts inferred: " <> show (factCount watcher))
  case solutionIfKnown watcher of
    Just solution -> log ("The watcher has solved it: " <> describeSuggestion solution)
    Nothing -> log "The watcher has not (yet) pinned down the full solution."

printHands :: Result -> Effect Unit
printHands result =
  for_ (allPlayers result.playerCount) \p ->
    log (playerName p <> "'s hand: " <> String.joinWith ", " (map displayName (handOf p)))
  where
  hands = case Array.head result.log of
    Just (GameDealt d) -> d.hands
    _ -> Map.empty

  handOf :: PlayerId -> Array Card
  handOf p = Set.toUnfoldable (fromMaybe Set.empty (Map.lookup p hands))

-- | The classic detective notepad: a row per card, a column per player
-- | plus the envelope. ✓ known held, ✗ known not held, · unknown.
renderGrid :: PlayerCount -> Knowledge -> String
renderGrid count knowledge =
  String.joinWith "\n" (Array.cons header (map row allCards)) <> "\n"
  where
  players = allPlayers count
  labelWidth = 16

  pad s = s <> power " " (max 0 (labelWidth - String.length s))

  header = pad "" <> String.joinWith " " (map playerName players) <> "  Env"

  row card = pad (displayName card)
    <> String.joinWith " " (map (cell card) players)
    <> "   "
    <> envelopeCell card

  cell card p
    | Set.member card (holdsOf knowledge p) = "✓"
    | Set.member card (lacksOf knowledge p) = "✗"
    | otherwise = "·"

  envelopeCell card
    | Set.member card (envelopeIn knowledge) = "✓"
    | Set.member card (envelopeOut knowledge) = "✗"
    | otherwise = "·"
