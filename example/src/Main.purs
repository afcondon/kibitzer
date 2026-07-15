-- | Run a seeded game and print both sides of the split screen: the
-- | ground-truth transcript, then the watcher's notebook — everything a
-- | non-player deduced without ever seeing a card.
-- |
-- |   spago run -p kibitzer-example -- 42 [--moves] [--players N]
-- |   spago run -p kibitzer-example -- stats [seeds]
-- |
-- | The stats mode compares the watcher's fortunes across table sizes and
-- | the classic/movement variants over many seeded games.
module Example.Main where

import Prelude

import Data.Array as Array
import Data.Foldable (for_, traverse_)
import Example.Orbits (runOrbits)
import Example.Skylines (runSkylines)
import Data.Int as Int
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
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
import Kibitzer.Player (PlayerCount, PlayerId(..), allPlayers, defaultPlayerCount, handSizes, mkPlayerCount, playerCountToInt)
import Kibitzer.Suggestion (suggestionCards)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Node.Process (argv)

main :: Effect Unit
main = do
  args <- argv
  let
    rest = Array.drop 2 args
    -- usage: [seed] [--moves] [--players N] — the seed comes first
    seedInt = fromMaybe 42 (Int.fromString =<< Array.head rest)
    movement = Array.elem "--moves" rest
    count = fromMaybe defaultPlayerCount do
      i <- Array.elemIndex "--players" rest
      n <- Int.fromString =<< Array.index rest (i + 1)
      mkPlayerCount n
  case Array.head rest of
    Just "stats" -> runStats (fromMaybe 100 (Int.fromString =<< Array.index rest 1))
    Just "corpus" -> runCorpus (fromMaybe 100 (Int.fromString =<< Array.index rest 1))
    Just "skylines" -> runSkylines
    Just "orbits" -> runOrbits
    _ -> run count movement seedInt

run :: PlayerCount -> Boolean -> Int -> Effect Unit
run count movement seedInt = do
  let
    result = simulate
      { playerCount: count
      , seed: mkSeed seedInt
      , policy: randomLegalPolicy
      , maxTurns: 600
      , movement
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

-- | One row of the stats table: everything is kept as running Int sums;
-- | means are computed at render time.
type RowStats =
  { games :: Int
  , events :: Int
  , suggestions :: Int
  , winTurns :: Int
  , facts :: Int
  , envKnown :: Int
  , solved :: Int
  , unfinished :: Int
  }

runStats :: Int -> Effect Unit
runStats n = do
  log
    ( "kibitzer stats — " <> show n <> " seeds per row (seeds 1.." <> show n
        <> "), policy: randomLegal, watcher sees 0 cards throughout\n"
    )
  log statsHeader
  for_ statsConfigs \(Tuple count movement) ->
    log (renderStatsRow count movement (rowFor count movement n))

statsConfigs :: Array (Tuple PlayerCount Boolean)
statsConfigs = do
  count <- Array.mapMaybe mkPlayerCount [ 3, 4, 5, 6 ]
  movement <- [ false, true ]
  pure (Tuple count movement)

rowFor :: PlayerCount -> Boolean -> Int -> RowStats
rowFor count movement n = Array.foldl accumulate empty (Array.range 1 n)
  where
  empty =
    { games: 0, events: 0, suggestions: 0, winTurns: 0
    , facts: 0, envKnown: 0, solved: 0, unfinished: 0
    }

  accumulate acc seedInt =
    let
      result = simulate
        { playerCount: count
        , seed: mkSeed seedInt
        , policy: randomLegalPolicy
        , maxTurns: 600
        , movement
        }
      watcher = knowledgeAt count Watcher (Array.length result.log) result.log
      isSuggestion = case _ of
        SuggestionMade _ -> true
        _ -> false
    in
      { games: acc.games + 1
      , events: acc.events + Array.length result.log
      , suggestions: acc.suggestions + Array.length (Array.filter isSuggestion result.log)
      , winTurns: acc.winTurns + result.turns
      , facts: acc.facts + factCount watcher
      , envKnown: acc.envKnown + Set.size (envelopeIn watcher)
      , solved: acc.solved + if isJust (solutionIfKnown watcher) then 1 else 0
      , unfinished: acc.unfinished + if isJust result.winner then 0 else 1
      }

-- | Emit every stats-mode game as one JSON object per line — the corpus
-- | the SMT "optimal watcher" (smt/optimal_watcher.py) analyses. Only
-- | watcher-visible information goes in `events` (passes and shows, with
-- | the three suggested cards); the solution rides along solely for
-- | scoring. Cards are indices into `allCards`; the Python side mirrors
-- | that list.
runCorpus :: Int -> Effect Unit
runCorpus n =
  for_ statsConfigs \(Tuple count movement) ->
    for_ (Array.range 1 n) \seedInt ->
      log (gameJson count movement seedInt)

gameJson :: PlayerCount -> Boolean -> Int -> String
gameJson count movement seedInt =
  jObj
    [ Tuple "seed" (show seedInt)
    , Tuple "players" (show (playerCountToInt count))
    , Tuple "movement" (if movement then "true" else "false")
    , Tuple "handSizes" (jArr (map sizeOf players))
    , Tuple "solution" (ixSet (suggestionCards result.solution))
    , Tuple "events" (jArr (Array.mapMaybe eventJson result.log))
    , Tuple "watcher" watcherJson
    ]
  where
  result = simulate
    { playerCount: count
    , seed: mkSeed seedInt
    , policy: randomLegalPolicy
    , maxTurns: 600
    , movement
    }

  watcher = knowledgeAt count Watcher (Array.length result.log) result.log

  players = allPlayers count

  sizeOf p = show (fromMaybe 0 (Map.lookup p (handSizes count)))

  cardIx c = fromMaybe (-1) (Array.elemIndex c allCards)

  ixSet s = jArr (map (show <<< cardIx) (Set.toUnfoldable s))

  eventJson = case _ of
    Passed { player: PlayerId p, suggestion } -> Just
      ( jObj
          [ Tuple "type" (jStr "pass")
          , Tuple "player" (show p)
          , Tuple "cards" (ixSet (suggestionCards suggestion))
          ]
      )
    CardShown { by: PlayerId b, suggestion } -> Just
      ( jObj
          [ Tuple "type" (jStr "show")
          , Tuple "by" (show b)
          , Tuple "cards" (ixSet (suggestionCards suggestion))
          ]
      )
    _ -> Nothing

  watcherJson = jObj
    [ Tuple "envelopeIn" (ixSet (envelopeIn watcher))
    , Tuple "envelopeOut" (ixSet (envelopeOut watcher))
    , Tuple "holds" (jArr (map (\p -> ixSet (holdsOf watcher p)) players))
    , Tuple "lacks" (jArr (map (\p -> ixSet (lacksOf watcher p)) players))
    ]

-- Minimal JSON assembly — every string we emit is from a fixed,
-- escape-free vocabulary.
jStr :: String -> String
jStr s = "\"" <> s <> "\""

jArr :: Array String -> String
jArr xs = "[" <> String.joinWith "," xs <> "]"

jObj :: Array (Tuple String String) -> String
jObj fields =
  "{" <> String.joinWith "," (map (\(Tuple k v) -> jStr k <> ":" <> v) fields) <> "}"

statsHeader :: String
statsHeader =
  padRight 8 "players"
    <> padRight 7 "moves"
    <> padLeft 12 "mean-events"
    <> padLeft 11 "mean-suggs"
    <> padLeft 14 "mean-win-turn"
    <> padLeft 14 "watcher-facts"
    <> padLeft 12 "env-known/3"
    <> padLeft 9 "solved%"
    <> padLeft 11 "unfinished"

renderStatsRow :: PlayerCount -> Boolean -> RowStats -> String
renderStatsRow count movement row =
  padRight 8 (show (playerCountToInt count))
    <> padRight 7 (if movement then "on" else "off")
    <> padLeft 12 (meanOf row.events)
    <> padLeft 11 (meanOf row.suggestions)
    <> padLeft 14 (meanOf row.winTurns)
    <> padLeft 14 (meanOf row.facts)
    <> padLeft 12 (meanOf row.envKnown)
    <> padLeft 9 (percentOf row.solved)
    <> padLeft 11 (show row.unfinished)
  where
  meanOf total = fixed1 total row.games
  percentOf count' = show ((100 * count' + row.games / 2) / max 1 row.games) <> "%"

-- | `fixed1 total n` — total/n to one decimal place, without printf.
fixed1 :: Int -> Int -> String
fixed1 total n =
  let
    tenths = (10 * total + n / 2) / max 1 n
  in
    show (tenths / 10) <> "." <> show (tenths `mod` 10)

padLeft :: Int -> String -> String
padLeft width s = power " " (max 0 (width - String.length s)) <> s

padRight :: Int -> String -> String
padRight width s = s <> power " " (max 0 (width - String.length s))

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
