-- | Animation state for the cascade view, in the style of the Hylograph
-- | ForcePlayground demo: enter progress lives in a `Map key Progress`,
-- | exits carry their frozen mark in a `Transitioning`, and a tick
-- | advances both. The scene is rebuilt from scratch every tick — there
-- | is no retained animation machinery, just pure data and `lerp`.
-- |
-- | The depth stagger is exact: a fact of derivation depth d starts at
-- | negative progress, so it renders as not-yet-started until the facts
-- | it was derived from have already landed.
module Kibitzer.Frontend.Cascade.Anim
  ( FactMark
  , Glyph(..)
  , RenderMark
  , CascadeAnim
  , emptyAnim
  , animActive
  , tickAnim
  , enterDelta
  , factKey
  , mkMark
  , syncAnim
  , renderMarks
  ) where

import Prelude

import Data.Array as Array
import Data.FoldableWithIndex (foldlWithIndex)
import Data.Int (toNumber)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Hylograph.Transition.Tick (Progress, Transitioning)
import Hylograph.Transition.Tick as Tick
import Kibitzer.Describe (describeFact)
import Kibitzer.Frontend.Cascade.Layout (claimCell)
import Kibitzer.Knowledge (Claim(..), Fact, FactId(..))
import Kibitzer.Player (PlayerCount)

data Glyph = GHolds | GLacks | GEnvIn | GEnvOut

derive instance Eq Glyph

-- | A fact as a dot on the notebook: where it sits, what it looks like,
-- | and its provenance as a native hover tooltip.
type FactMark =
  { key :: String
  , x :: Number
  , y :: Number
  , glyph :: Glyph
  , tip :: String
  }

-- | A mark plus its animation state, resolved for one tick of rendering.
type RenderMark =
  { mark :: FactMark
  , enterProgress :: Maybe Number
  , exitProgress :: Maybe Number
  }

type CascadeAnim =
  { entering :: Map String Progress
  , exiting :: Array (Transitioning FactMark)
  }

emptyAnim :: CascadeAnim
emptyAnim = { entering: Map.empty, exiting: [] }

animActive :: CascadeAnim -> Boolean
animActive anim = not (Map.isEmpty anim.entering) || not (Array.null anim.exiting)

-- | Progress advanced per frame; completed entries simply drop out.
enterDelta :: Number
enterDelta = Tick.ticksForDuration 450

tickAnim :: Number -> CascadeAnim -> CascadeAnim
tickAnim delta anim =
  { entering: (Tick.tickProgressMap delta anim.entering).active
  , exiting: (Tick.tickTransitions delta anim.exiting).active
  }

factKey :: Fact -> String
factKey f = case f.id of FactId n -> "f" <> show n

mkMark :: PlayerCount -> Fact -> FactMark
mkMark count f =
  let
    cell = claimCell count f.claim
  in
    { key: factKey f
    , x: cell.x
    , y: cell.y
    , glyph: case f.claim of
        Holds _ _ -> GHolds
        Lacks _ _ -> GLacks
        InEnvelope _ -> GEnvIn
        NotInEnvelope _ -> GEnvOut
    , tip: describeFact f
    }

-- | Beyond this many arrivals (a jump-to-end, not a step), animation is
-- | skipped and the notebook just appears — a cascade of 100 is noise.
animationCap :: Int
animationCap = 40

-- | Reconcile animation state with a timeline move. The fact feed is
-- | append-only, so the diff between two positions is a suffix: facts
-- | gained scrubbing forward enter (staggered by derivation depth), facts
-- | lost scrubbing backward fade out in place, and anything that changed
-- | its mind mid-flight is handed from one structure to the other.
syncAnim
  :: PlayerCount
  -> Map FactId Int -- derivation depth of every fact (frame-local)
  -> Array Fact -- facts visible at the old position
  -> Array Fact -- facts visible at the new position
  -> CascadeAnim
  -> CascadeAnim
syncAnim count depths oldFacts newFacts anim
  | Array.length newFacts >= Array.length oldFacts =
      let
        added = Array.drop (Array.length oldFacts) newFacts
        addedKeys = Set.fromFoldable (map factKey added)
        entering =
          if Array.length added > animationCap then anim.entering
          else foldlWithIndex
            ( \i m f ->
                Map.insert (factKey f) (startingProgress depths i f) m
            )
            anim.entering
            added
      in
        { entering
        , exiting: Array.filter (\t -> not (Set.member t.item.key addedKeys)) anim.exiting
        }
  | otherwise =
      let
        removed = Array.drop (Array.length newFacts) oldFacts
        removedKeys = Set.fromFoldable (map factKey removed)
        stillShown = Array.filter (\t -> not (Set.member t.item.key removedKeys)) anim.exiting
        departing =
          if Array.length removed > animationCap then []
          else Tick.startTransitions (map (mkMark count) removed)
      in
        { entering: Map.filterKeys (\k -> not (Set.member k removedKeys)) anim.entering
        , exiting: stillShown <> departing
        }

-- | Negative initial progress = an exact per-fact delay: depth leads,
-- | feed order breaks ties, and the lead is capped so a long avalanche
-- | still completes promptly.
startingProgress :: Map FactId Int -> Int -> Fact -> Progress
startingProgress depths i f =
  max (-2.5) (-(0.18 * toNumber depth + 0.045 * toNumber i))
  where
  depth = fromMaybe 0 (Map.lookup f.id depths)

-- | Resolve every visible fact against the animation state for one tick.
renderMarks :: PlayerCount -> Array Fact -> CascadeAnim -> Array RenderMark
renderMarks count visible anim =
  map live visible <> map dying anim.exiting
  where
  live f =
    let
      mark = mkMark count f
    in
      { mark, enterProgress: Map.lookup mark.key anim.entering, exitProgress: Nothing }

  dying t = { mark: t.item, enterProgress: Nothing, exitProgress: Just t.progress }
