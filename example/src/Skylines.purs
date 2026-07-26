-- | A page of derivation skylines: the DAG view as small multiples,
-- | curated for genuinely different outcomes — shallow sweeps next to
-- | six-deep cathedrals, watcher wins next to games that never close.
-- | Emits a self-contained HTML page (stdout); the Makefile drops it at
-- | frontend/public/skylines.html.
module Example.Skylines (Sample, runSkylines, curate, caption) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl, maximum)
import Data.Int (toNumber)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String (joinWith)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested (type (/\), (/\))
import Effect (Effect)
import Effect.Console (log)
import Kibitzer.Cascade (globalDepths)
import Kibitzer.Game (Result, simulate)
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (Claim(..), Fact, FactId(..), Knowledge, facts, solutionIfKnown)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (PlayerCount, defaultPlayerCount, mkPlayerCount, playerCountToInt)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)

type Sample =
  { seedInt :: Int
  , players :: Int
  , movement :: Boolean
  , allFacts :: Array Fact
  , depths :: Map FactId Int
  , maxDepth :: Int
  , solvedAt :: Maybe Int -- timeline position, if the watcher ever solves
  , events :: Int
  }

play :: Int -> Int -> Boolean -> Sample
play seedInt players movement =
  let
    count = fromMaybe defaultPlayerCount (mkPlayerCount players)
    result = simulate
      { playerCount: count
      , seed: mkSeed seedInt
      , policy: randomLegalPolicy
      , maxTurns: 600
      , movement
      }
    snapshots = knowledgeTimeline count Watcher result.log
    allFacts = fromMaybe [] (map facts (Array.last snapshots))
    depths = globalDepths allFacts
  in
    { seedInt
    , players
    , movement
    , allFacts
    , depths
    , maxDepth: fromMaybe 0 (maximum (Map.values depths))
    , solvedAt: Array.findIndex (isJust <<< solutionIfKnown) snapshots
    , events: Array.length result.log
    }

-- | Play a spread of games, keep exemplars: per configuration the
-- | deepest DAG and the earliest watcher win, plus the maximum break
-- | (every card located) if one turns up.
-- | A thunk, not a CAF: 200 games are heavy, and a top-level value
-- | binding would be forced at module load — hanging *every* CLI
-- | subcommand (trace, etc.) that merely imports this module. Taking a
-- | `Unit` defers the work to the pages that actually draw it.
curate :: Unit -> Array Sample
curate _ =
  let
    configs = [ 3 /\ false, 4 /\ false, 5 /\ false, 6 /\ false, 6 /\ true ]
    pool = configs # Array.concatMap \(p /\ mv) ->
      map (\s -> play s p mv) (Array.range 1 40)

    deepest c = pickBest (comparing _.maxDepth) (ofConfig c)
    earliestWin c = pickBest (comparing winMargin) solvedOf
      where
      solvedOf = Array.filter (isJust <<< _.solvedAt) (ofConfig c)
    ofConfig (p /\ mv) = Array.filter (\s -> s.players == p && s.movement == mv) pool
    pickBest cmp xs = Array.last (Array.sortBy cmp xs)
    winMargin s = case s.solvedAt of
      Just at -> s.events - at -- events to spare before the reveal
      Nothing -> -1
    maximumBreak = Array.find
      (\s -> Array.length s.allFacts == 21 * (s.players + 1))
      pool
  in
    Array.nubBy (comparing key)
      ( Array.catMaybes
          ( map (deepest >>> identity) configs
              <> map (earliestWin >>> identity) configs
              <> [ maximumBreak ]
          )
      )
  where
  key s = show s.seedInt <> "/" <> show s.players <> "/" <> show s.movement

-- ---------------------------------------------------------------- SVG

svgW :: Number
svgW = 340.0

svgH :: Number
svgH = 210.0

skylineSvg :: Sample -> String
skylineSvg s =
  "<svg viewBox=\"0 0 340 210\" width=\"340\">"
    <> joinWith "" (map level (Array.range 0 s.maxDepth))
    <> joinWith "" (Array.mapMaybe edge s.allFacts)
    <> joinWith "" (map mark s.allFacts)
    <> "</svg>"
  where
  total = toNumber (max 1 (Array.length s.allFacts))

  levelGap = min 42.0 (160.0 / toNumber (max 1 s.maxDepth))

  xOf (FactId n) = 12.0 + (toNumber n + 0.5) / total * (svgW - 24.0)

  yOf fid = 190.0 - toNumber (fromMaybe 0 (Map.lookup fid s.depths)) * levelGap

  level d =
    let
      y = 190.0 - toNumber d * levelGap
    in
      "<line x1=\"10\" y1=\"" <> show y <> "\" x2=\"330\" y2=\"" <> show y
        <> "\" stroke=\"#eeeeee\" stroke-width=\"1\"/>"

  edge f = case f.justification.premises of
    [] -> Nothing
    ps -> Just $ joinWith "" $ ps <#> \p ->
      "<line x1=\"" <> show (xOf p) <> "\" y1=\"" <> show (yOf p)
        <> "\" x2=\"" <> show (xOf f.id) <> "\" y2=\"" <> show (yOf f.id)
        <> "\" stroke=\"#141414\" stroke-width=\"0.6\" opacity=\"0.3\"/>"

  mark f =
    let
      x = show (xOf f.id)
      y = show (yOf f.id)
      dot r fill = "<circle cx=\"" <> x <> "\" cy=\"" <> y <> "\" r=\"" <> r
        <> "\" fill=\"" <> fill <> "\"/>"
    in
      case f.claim of
        Holds _ _ -> dot "2.6" "#141414"
        InEnvelope _ -> dot "3.1" "#d92b2b"
        Lacks _ _ -> dot "1.3" "#c9c9c9"
        NotInEnvelope _ -> dot "1.7" "#e5a9a9"

caption :: Sample -> String
caption s =
  "seed " <> show s.seedInt
    <> " · " <> show s.players <> "p"
    <> (if s.movement then " · board" else "")
    <> " · " <> show (Array.length s.allFacts) <> " facts"
    <> " · depth " <> show s.maxDepth
    <> case s.solvedAt of
      Just at ->
        if Array.length s.allFacts == 21 * (s.players + 1) then
          " · <strong class=\"win\">maximum break</strong>"
        else
          let
            margin = s.events - at
            unit_ = if margin == 1 then " event" else " events"
          in
            " · <strong class=\"win\">watcher solves, "
              <> show margin
              <> unit_ <> " to spare</strong>"
      Nothing -> " · unsolved"

-- | The pool is expensive (200 games). PureScript is strict, so a
-- | module-level value would run at import — hanging every other
-- | subcommand that merely imports this module. One `<-` bind defers the
-- | work into the action's closure, so `curate` runs only when this
-- | command runs.
runSkylines :: Effect Unit
runSkylines = do
  u <- pure unit
  log (skylinesPage (curate u))

skylinesPage :: Array Sample -> String
skylinesPage samples =
  page
  where
  figure s =
    "<figure>" <> skylineSvg s
      <> "<figcaption>" <> caption s <> "</figcaption></figure>"

  page =
    """<!doctype html><meta charset="utf-8">
<title>kibitzer — derivation skylines</title>
<style>
 body { font-family: "Helvetica Neue", Arial, sans-serif; color: #111;
        max-width: 76rem; margin: 2rem auto; padding: 0 1.5rem; }
 h1 { font-size: 1.4rem; letter-spacing: -0.01em; }
 p { max-width: 62ch; color: #444; font-size: .9rem; }
 .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
         gap: 1.5rem 2rem; margin-top: 1.5rem; }
 figure { margin: 0; }
 figcaption { font-size: .72rem; color: #767676; margin-top: .3rem;
              letter-spacing: .02em; }
 figcaption .win { color: #d92b2b; font-weight: 600; }
</style>
<h1>Derivation skylines</h1>
<p>Every game the watcher observes builds a different argument. Each panel is
one game's complete derivation DAG: facts in feed order along the x-axis,
derivation depth as storeys — grey dots are eliminations, black dots located
cards, red dots envelope certainties; every line cites the premises a
deduction consumed. Some games are shallow sweeps of direct observation;
some build towers fifteen inferences tall.</p>
<div class="grid">"""
      <> joinWith "\n" (map figure samples)
      <> "</div>"
