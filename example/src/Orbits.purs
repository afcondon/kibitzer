-- | The radial DAG as small multiples: the same curated games as the
-- | skylines page, each derivation graph bent into orbits — depth as
-- | radius, observations outermost, the envelope certainties pulled to
-- | the bullseye. Static analytic layout (chronological angle, exact
-- | rings): no force simulation in a printed page, and none needed —
-- | the forces exist to keep a *live* population legible.
-- | Emits a self-contained HTML page (stdout); the Makefile drops it at
-- | frontend/public/orbits.html.
module Example.Orbits (runOrbits) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Number (cos, pi, sin)
import Data.String (joinWith)
import Effect (Effect)
import Effect.Console (log)
import Example.Skylines (Sample, caption, curate)
import Kibitzer.Knowledge (Claim(..), Fact, FactId(..))

-- panel geometry: a 320×320 viewBox, everything relative to its centre
half :: Number
half = 160.0

outerR :: Number
outerR = 138.0

innerFloor :: Number
innerFloor = 42.0

orbitSvg :: Sample -> String
orbitSvg s =
  "<svg viewBox=\"0 0 320 320\" width=\"320\">"
    <> joinWith "" (map ring (Array.range 0 s.maxDepth))
    <> bullseye
    <> joinWith "" (Array.mapMaybe edge s.allFacts)
    <> joinWith "" (map mark s.allFacts)
    <> "</svg>"
  where
  total = toNumber (max 1 (Array.length s.allFacts))

  gap = min 46.0 ((outerR - innerFloor) / toNumber (max 1 s.maxDepth))

  radiusOf :: Fact -> Number
  radiusOf f = case f.claim of
    -- the certainties cluster at the bullseye; a tiny spread keeps the
    -- three dots legible as three
    InEnvelope _ -> 6.0
    _ -> outerR - toNumber (fromMaybe 0 (Map.lookup f.id s.depths)) * gap

  posOf :: Fact -> { x :: Number, y :: Number }
  posOf f =
    let
      FactId n = f.id
      a = 2.0 * pi * (toNumber n + 0.5) / total - pi / 2.0
      r = radiusOf f
    in
      { x: half + r * cos a, y: half + r * sin a }

  ring d =
    "<circle cx=\"160\" cy=\"160\" r=\"" <> show (outerR - toNumber d * gap)
      <> "\" fill=\"none\" stroke=\"#eeeeee\" stroke-width=\"1\"/>"

  bullseye =
    "<circle cx=\"160\" cy=\"160\" r=\"11\" fill=\"none\" stroke=\"#d92b2b\""
      <> " stroke-width=\"0.8\" stroke-dasharray=\"2 3\" opacity=\"0.55\"/>"

  edge f = case f.justification.premises of
    [] -> Nothing
    ps -> Just $ joinWith "" $ ps <#> \p -> fromMaybe "" do
      let FactId n = p
      pf <- Array.index s.allFacts n
      let a = posOf pf
      let b = posOf f
      pure
        ( "<line x1=\"" <> show a.x <> "\" y1=\"" <> show a.y
            <> "\" x2=\"" <> show b.x <> "\" y2=\"" <> show b.y
            <> "\" stroke=\"#141414\" stroke-width=\"0.6\" opacity=\"0.3\"/>"
        )

  mark f =
    let
      p = posOf f
      dot r fill = "<circle cx=\"" <> show p.x <> "\" cy=\"" <> show p.y
        <> "\" r=\"" <> r <> "\" fill=\"" <> fill <> "\"/>"
    in
      case f.claim of
        Holds _ _ -> dot "2.6" "#141414"
        InEnvelope _ -> dot "3.1" "#d92b2b"
        Lacks _ _ -> dot "1.3" "#c9c9c9"
        NotInEnvelope _ -> dot "1.7" "#e5a9a9"

runOrbits :: Effect Unit
runOrbits = log page
  where
  samples = curate

  figure s =
    "<figure>" <> orbitSvg s
      <> "<figcaption>" <> caption s <> "</figcaption></figure>"

  page =
    """<!doctype html><meta charset="utf-8">
<title>kibitzer — derivation orbits</title>
<style>
 body { font-family: "Helvetica Neue", Arial, sans-serif; color: #111;
        max-width: 76rem; margin: 2rem auto; padding: 0 1.5rem; }
 h1 { font-size: 1.4rem; letter-spacing: -0.01em; }
 p { max-width: 62ch; color: #444; font-size: .9rem; }
 .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
         gap: 1.5rem 2rem; margin-top: 1.5rem; }
 figure { margin: 0; }
 figcaption { font-size: .72rem; color: #767676; margin-top: .3rem;
              letter-spacing: .02em; }
 figcaption .win { color: #d92b2b; font-weight: 600; }
</style>
<h1>Derivation orbits</h1>
<p>The same curated games as the skylines page, bent into circles: each
panel is one game's complete derivation DAG with time sweeping clockwise
from twelve o'clock and depth as radius — direct observations on the
outermost ring, derivations collapsing inward, and the envelope
certainties (red) pulled to the bullseye. The argument literally closes
in on the truth; a game the watcher never cracks leaves the bullseye
short of its three.</p>
<div class="grid">"""
      <> joinWith "\n" (map figure samples)
      <> "</div>"
