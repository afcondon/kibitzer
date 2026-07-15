-- | The cascade column as a child component — the one piece of the app
-- | that owns real resources: the HATS-managed SVG under `#cascade-view`,
-- | the force-simulation handle, and the requestAnimationFrame loop that
-- | drives both views' choreography. All of that lifecycle lives behind
-- | this boundary now; the parent just passes `{ game, position }` down
-- | and receives scrub intents back (sparkline bar clicks).
-- |
-- | `receive` is the seam: a position change reconciles the animation
-- | state against the fact diff (the scrub choreography); a genuinely
-- | different game tears the view down and rebuilds; a hover change is
-- | a light repaint. One instance runs one mode for its lifetime —
-- | `packView` picks packs or grid at mount, and the cross-referenced
-- | page mounts one of each, so each mode owns a distinct container id.
-- | The grid sub-toggles (layout, wiring) are local state — no one
-- | outside this column cares.
module Kibitzer.Frontend.Component.CascadeHost
  ( Input
  , Output(..)
  , Slot
  , component
  ) where

import Prelude

import Data.Array as Array
import Data.Const (Const)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Set as Set
import Data.Time.Duration (Milliseconds(..))
import Effect.Aff (delay)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Hylograph.Simulation (Engine(..), SimulationHandle, runSimulation)
import Hylograph.Transition.RAF as RAF
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cascade (globalDepths)
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim, animActive, emptyAnim, enterDelta, syncAnim, tickAnim)
import Kibitzer.Frontend.Cascade.Layout (GridLayout(..))
import Kibitzer.Frontend.Cascade.Radial (RadialRow)
import Kibitzer.Frontend.Cascade.Radial as Radial
import Kibitzer.Frontend.Cascade.Scene (clearView, renderChrome)
import Kibitzer.Frontend.Cascade.View (redraw)
import Kibitzer.Frontend.Crossref as Crossref
import Kibitzer.Frontend.Packs.Model (PackRow, PossInfo)
import Kibitzer.Frontend.Packs.Model as Packs
import Kibitzer.Frontend.Packs.View (PacksAnim)
import Kibitzer.Frontend.Packs.View as PacksView
import Kibitzer.Frontend.Types (Game, currentKnowledge)
import Kibitzer.Knowledge (Fact, FactId(..), facts)
import Kibitzer.Player (playerCountToInt)
import Data.Foldable (maximum)

type Input =
  { game :: Game
  , position :: Int
  , packView :: Boolean -- packs (true) or the grid; fixed per instance
  , hover :: Maybe Crossref.Hover -- the page-wide cross-reference hover
  }

data Output
  = ScrubRequested Int -- a sparkline bar click: the parent owns the timeline, we ask
  | HoverChanged (Maybe Crossref.Hover) -- something under this host's pointer

type Slot = H.Slot (Const Void) Output Unit

type State =
  { game :: Game
  , position :: Int
  , cascadeAnim :: CascadeAnim
  , animPending :: Boolean -- an animation frame is already scheduled
  , viewReady :: Boolean -- chrome is in the DOM; false inside initView's teardown window
  , animListener :: Maybe (HS.Listener Action)
  , wiring :: Boolean -- keep settled provenance hairlines visible
  , gridLayout :: GridLayout -- the grid's target arrangement
  , layoutFrom :: GridLayout -- where the morph started
  , layoutT :: Number -- morph progress, 0 = from, 1 = to
  , packView :: Boolean -- mirror of the input; packs (true) or the grid
  , simHandle :: Maybe (SimulationHandle PackRow)
  , packStates :: Map Int PossInfo -- possibility states at the current position
  , packsAnim :: PacksAnim
  , radialHandle :: Maybe (SimulationHandle RadialRow) -- alive while the radial layout is in play
  , radialPos :: Map Int { x :: Number, y :: Number } -- last-read orbit positions by fact id
  , hover :: Maybe Crossref.Hover -- mirror of the input
  }

data Action
  = Initialize
  | Finalize
  | Receive Input
  | AnimTick
  | ToggleWiring Boolean
  | SetGridLayout GridLayout
  | TokenHovered (Maybe Int)
  | BubbleHovered (Maybe { loc :: Int, card :: Int })
  | BarClicked Int

component :: forall q m. MonadAff m => H.Component q Input Output m
component = H.mkComponent
  { initialState: \input ->
      { game: input.game
      , position: input.position
      , cascadeAnim: emptyAnim
      , animPending: false
      , viewReady: false
      , animListener: Nothing
      , wiring: true
      , gridLayout: RadialView
      , layoutFrom: RadialView
      , layoutT: 1.0
      , packView: input.packView
      , simHandle: Nothing
      , packStates: Map.empty
      , packsAnim: PacksView.emptyPacksAnim
      , radialHandle: Nothing
      , radialPos: Map.empty
      , hover: input.hover
      }
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , initialize = Just Initialize
      , finalize = Just Finalize
      , receive = Just <<< Receive
      }
  }

type HostM m = H.HalogenM State Action () Output m Unit

handleAction :: forall m. MonadAff m => Action -> HostM m
handleAction = case _ of
  Initialize -> do
    -- the animation-frame channel: RAF callbacks notify AnimTick through
    -- here, back into ordinary Halogen evaluation
    { emitter, listener } <- liftEffect HS.create
    void (H.subscribe emitter)
    H.modify_ _ { animListener = Just listener }
    initView
  Finalize -> do
    stopPacksSim
    stopRadialSim
  Receive input -> do
    st <- H.get
    H.modify_ _
      { game = input.game
      , position = input.position
      , packView = input.packView
      , hover = input.hover
      }
    if gameKey input.game /= gameKey st.game || input.packView /= st.packView then do
      -- a genuinely different deal, or a packs/grid switch: tear down
      -- and rebuild from scratch
      stopPacksSim
      initView
    else if input.position /= st.position then do
      if st.packView then syncPacksMove st.position
      else syncCascadeMove st.position input.position
    else when (input.hover /= st.hover) do
      -- a hover change alone: repaint the moving layer in place
      if st.packView then drawPacksFrame
      else redrawCascade
  -- one animation frame: advance progress, redraw, and keep the loop
  -- alive only while something is still moving. A frame scheduled before
  -- a view teardown can land while the chrome is gone — the viewReady
  -- gate drops it; initView restarts whatever loop is needed.
  AnimTick -> do
    H.modify_ _ { animPending = false }
    st <- H.get
    if not st.viewReady then pure unit
    else if st.packView then packsAnimFrame
    else do
      let
        t' = min 1.0 (st.layoutT + Tick.ticksForDuration 550)
        anim = tickAnim enterDelta st.cascadeAnim
      -- read the orbit simulation's live positions while it's in play
      radialPos <- case st.radialHandle of
        Just handle -> liftEffect (map Radial.positionMap handle.getNodes)
        Nothing -> pure st.radialPos
      alpha <- case st.radialHandle of
        Just handle -> liftEffect handle.getAlpha
        Nothing -> pure 0.0
      H.modify_ _ { cascadeAnim = anim, layoutT = t', radialPos = radialPos }
      -- fully morphed away from the radial layout: the sim can retire
      when (t' >= 1.0 && st.gridLayout /= RadialView) stopRadialSim
      redrawCascade
      when
        ( animActive anim
            || t' < 1.0
            || (st.gridLayout == RadialView && alpha > 0.0015)
        )
        scheduleAnimFrame
  ToggleWiring b -> do
    H.modify_ _ { wiring = b }
    redrawCascade
  -- the morph itself is animated by the frame loop; this just sets a new
  -- target. Re-selecting the layout we're mid-flight from just reverses
  -- the journey; any other target restarts from the current arrangement.
  SetGridLayout l -> do
    st <- H.get
    when (l /= st.gridLayout) do
      let reversing = l == st.layoutFrom && st.layoutT < 1.0
      H.modify_ _
        { gridLayout = l
        , layoutFrom = st.gridLayout
        , layoutT = if reversing then 1.0 - st.layoutT else 0.0
        }
      when (l == RadialView) ensureRadialSim
      scheduleAnimFrame
  TokenHovered t -> H.raise (HoverChanged (map Crossref.HoverFact t))
  BubbleHovered b -> H.raise (HoverChanged (map (\k -> Crossref.HoverPoss k.loc k.card) b))
  BarClicked i -> H.raise (ScrubRequested i)

-- | What makes two Game values the same game: the full deal
-- | configuration. The simulation is pure, so equal keys mean
-- | byte-identical games — a re-deal of the same config reads as a
-- | timeline move, which the position diff already handles.
gameKey :: Game -> { seed :: Int, players :: Int, movement :: Boolean }
gameKey game =
  { seed: game.seedInt
  , players: playerCountToInt game.result.playerCount
  , movement: game.movement
  }

-- | Entering the view (mount, re-deal, or packs/grid switch): wait a beat
-- | for Halogen to have mounted the empty container, then draw chrome and
-- | the current position from scratch — packs or grid, whichever is chosen.
initView :: forall m. MonadAff m => HostM m
initView = do
  H.modify_ _ { viewReady = false }
  H.liftAff (delay (Milliseconds 0.0))
  stopRadialSim -- a fresh deal or view switch invalidates the orbit sim
  st <- H.get
  liftEffect (clearView (containerSelector st))
  if st.packView then initPacks
  else do
    H.modify_ _
      { cascadeAnim = emptyAnim
      , layoutFrom = st.gridLayout
      , layoutT = 1.0
      }
    liftEffect (renderChrome st.game.result.playerCount)
    H.modify_ _ { viewReady = true }
    when (st.gridLayout == RadialView) ensureRadialSim
    redrawCascade

-- | Fresh simulation for the possibility packs: chrome, the survivors at
-- | the current position, orbit forces for the live disjunctions.
initPacks :: forall m. MonadAff m => HostM m
initPacks = do
  stopPacksSim
  st <- H.get
  let
    count = st.game.result.playerCount
    knowledge = currentKnowledge st.game st.position
    keep = Packs.survivorIds count knowledge
    nodes = Array.filter (\n -> Set.member n.id keep) (Packs.allTemplateNodes count)
  liftEffect (PacksView.renderPacksChrome count)
  H.modify_ _ { viewReady = true }
  result <- liftEffect $ runSimulation
    { engine: D3
    , setup: Packs.setupFor count (Packs.orbitSets knowledge)
    , nodes
    , links: ([] :: Array { source :: Int, target :: Int })
    , container: "#packs-bubbles"
    , alphaMin: 0.001
    }
  H.modify_ _
    { simHandle = Just result.handle
    , packStates = Packs.deriveStates count knowledge
    , packsAnim = PacksView.emptyPacksAnim
    }
  redrawPacksPosition
  scheduleAnimFrame

stopPacksSim :: forall m. MonadAff m => HostM m
stopPacksSim = do
  st <- H.get
  case st.simHandle of
    Just handle -> do
      liftEffect handle.stop
      H.modify_ _ { simHandle = Nothing }
    Nothing -> pure unit

-- | A timeline move in the packs view. The diff against the simulation's
-- | current population decides the choreography: fresh possibilities pop
-- | in at their pack, dead ones fly into the copy that absorbed them —
-- | a card proven into the envelope is *seen* being proven by its copies
-- | converging from every pack. Orbit membership follows the live
-- | disjunctions via a rebuilt force setup.
-- |
-- | Reheats are earned, not automatic: `updateData`/`updateSetup` both
-- | wake the simulation, so an event that moves nothing (a suggestion,
-- | a pass that only ghosts bubbles) must not call them — that was the
-- | tell-tale pulse on every step. States still refresh and repaint.
syncPacksMove :: forall m. MonadAff m => Int -> HostM m
syncPacksMove oldPos = do
  st <- H.get
  case st.simHandle of
    Nothing -> pure unit
    Just handle -> do
      let
        count = st.game.result.playerCount
        knowledge = currentKnowledge st.game st.position
        keep = Packs.survivorIds count knowledge
        orbits = Packs.orbitSets knowledge
        oldOrbits = Packs.orbitSets (currentKnowledge st.game oldPos)
      current <- liftEffect handle.getNodes
      let
        currentIds = Set.fromFoldable (map _.id current)
        removed = Array.filter (\n -> not (Set.member n.id keep)) current
        exits = removed <#> \n ->
          { id: n.id
          , x: n.x
          , y: n.y
          , card: n.card
          , targetId: do
              c <- Packs.cardAt n.card
              loc <- Packs.locationOf count knowledge c
              pure (Packs.nodeId loc n.card)
          }
        addedIds = Set.difference keep currentIds
        kept = Array.filter (\n -> Set.member n.id keep) current
        fresh = Array.filter (\n -> Set.member n.id addedIds) (Packs.allTemplateNodes count)
        popChanged = not (Array.null removed) || not (Set.isEmpty addedIds)
        orbitsChanged = orbits /= oldOrbits
      when popChanged do
        _ <- liftEffect $ handle.updateData (kept <> fresh) []
        pure unit
      when orbitsChanged
        (liftEffect $ handle.updateSetup (Packs.setupFor count orbits))
      H.modify_ _
        { packStates = Packs.deriveStates count knowledge
        , packsAnim =
            { entering:
                Tick.startProgress (Set.toUnfoldable addedIds)
                  (Map.filterKeys (\k -> Set.member k keep) st.packsAnim.entering)
            , exiting:
                Array.filter (\t -> not (Set.member t.item.id keep)) st.packsAnim.exiting
                  <> Tick.startTransitions exits
            }
        }
      redrawPacksPosition
      -- physics untouched: one repaint picks up state changes (ghosting)
      if popChanged || orbitsChanged then scheduleAnimFrame
      else drawPacksFrame

-- | A timeline move while the grid is showing: reconcile the animation
-- | state with the fact diff, keep the orbit simulation's population in
-- | step if it's alive, redraw, and (re)start the frame loop if anything
-- | is now in flight.
syncCascadeMove :: forall m. MonadAff m => Int -> Int -> HostM m
syncCascadeMove oldPos newPos = do
  st <- H.get
  let
    count = st.game.result.playerCount
    anim = syncAnim count st.game.depths
      (facts (currentKnowledge st.game oldPos))
      (facts (currentKnowledge st.game newPos))
      st.cascadeAnim
  H.modify_ _ { cascadeAnim = anim }
  syncRadialPopulation
  redrawCascade
  st' <- H.get
  when (animActive anim || isJust st'.radialHandle) scheduleAnimFrame

-- | The derivation DAG of the finished game, plus what's visible now —
-- | everything the radial simulation needs to know.
radialInputs
  :: State
  -> { visible :: Array Fact
     , depths :: Map FactId Int
     , maxDepth :: Int
     , total :: Int
     }
radialInputs st =
  let
    allFacts = fromMaybe [] (map facts (Array.last st.game.snapshots))
    depths = globalDepths allFacts
  in
    { visible: facts (currentKnowledge st.game st.position)
    , depths
    , maxDepth: fromMaybe 0 (maximum (Map.values depths))
    , total: Array.length allFacts
    }

-- | Start the orbit simulation at the current position. Nodes spawn at
-- | their analytic radial positions, so the first frame is already the
-- | right picture and the forces only refine it.
ensureRadialSim :: forall m. MonadAff m => HostM m
ensureRadialSim = do
  st <- H.get
  case st.radialHandle of
    Just _ -> pure unit
    Nothing -> do
      let
        ri = radialInputs st
        nodes = map (Radial.templateNode ri.depths ri.maxDepth ri.total) ri.visible
        links = Radial.linksFor ri.visible st.game.allEdges
      result <- liftEffect $ runSimulation
        { engine: D3
        , setup: Radial.setupFor ri.maxDepth
        , nodes
        , links
        , container: "#cascade-svg"
        , alphaMin: 0.001
        }
      H.modify_ _
        { radialHandle = Just result.handle
        , radialPos = Radial.positionMap nodes
        }
      scheduleAnimFrame

stopRadialSim :: forall m. MonadAff m => HostM m
stopRadialSim = do
  st <- H.get
  case st.radialHandle of
    Just handle -> do
      liftEffect handle.stop
      H.modify_ _ { radialHandle = Nothing, radialPos = Map.empty }
    Nothing -> pure unit

-- | A scrub while the orbit sim is alive: survivors keep their live
-- | positions, newborn facts spawn at their analytic slots, the links
-- | follow the visible premise DAG. `updateData` reheats — so it only
-- | runs when the population actually changed (an uninformative event
-- | must not make the whole web shiver).
syncRadialPopulation :: forall m. MonadAff m => HostM m
syncRadialPopulation = do
  st <- H.get
  case st.radialHandle of
    Nothing -> pure unit
    Just handle -> do
      let
        ri = radialInputs st
        visibleCount = Array.length ri.visible
      current <- liftEffect handle.getNodes
      let
        currentIds = Set.fromFoldable (map _.id current)
        kept = Array.filter (\n -> n.id < visibleCount) current
        fresh = ri.visible
          # Array.filter (\f -> let FactId n = f.id in not (Set.member n currentIds))
          # map (Radial.templateNode ri.depths ri.maxDepth ri.total)
      when (not (Array.null fresh) || Array.length kept /= Array.length current) do
        _ <- liftEffect $ handle.updateData (kept <> fresh)
          (Radial.linksFor ri.visible st.game.allEdges)
        pure unit

-- | Schedule exactly one animation frame; its callback re-enters Halogen
-- | as AnimTick. Self-perpetuating while animations are active — this is
-- | the whole RAF→Halogen bridge.
scheduleAnimFrame :: forall m. MonadAff m => HostM m
scheduleAnimFrame = do
  st <- H.get
  case st.animListener of
    Just listener | not st.animPending -> do
      H.modify_ _ { animPending = true }
      void $ liftEffect $ RAF.requestAnimationFrame \_ -> HS.notify listener AnimTick
    _ -> pure unit

-- | Each mode owns a container id so the packs and grid hosts can share
-- | a page without their HATS selectors colliding.
containerId :: State -> String
containerId st = if st.packView then "packs-view" else "cascade-view"

containerSelector :: State -> String
containerSelector st = "#" <> containerId st

-- | The cross-reference emphasis for the current hover, or Nothing.
implicatedNow :: State -> Maybe Crossref.Implicated
implicatedNow st = st.hover <#> Crossref.implicated
  st.game.result.playerCount
  (facts (currentKnowledge st.game st.position))

-- | Draw the grid's moving layers for the current state (chrome untouched).
redrawCascade :: forall m. MonadAff m => HostM m
redrawCascade = do
  st <- H.get
  case st.animListener of
    Just listener | st.viewReady ->
      liftEffect $ redraw
        { game: st.game
        , position: st.position
        , wiring: st.wiring
        , layout: { from: st.layoutFrom, to: st.gridLayout, t: st.layoutT }
        , radialPos: st.radialPos
        , hover: implicatedNow st
        , anim: st.cascadeAnim
        , onBar: \i -> HS.notify listener (BarClicked i)
        , onHoverFact: \fid -> HS.notify listener (TokenHovered fid)
        }
    _ -> pure unit

-- | The packs' per-position layer — the orbit guides.
redrawPacksPosition :: forall m. MonadAff m => HostM m
redrawPacksPosition = do
  st <- H.get
  liftEffect $ PacksView.renderPacksPosition
    { count: st.game.result.playerCount
    , orbits: Packs.orbitSets (currentKnowledge st.game st.position)
    }

-- | Rebuild the bubble layer from the simulation's current positions —
-- | the shared body of the frame loop and the hover repaint.
drawPacksFrame :: forall m. MonadAff m => HostM m
drawPacksFrame = do
  st <- H.get
  case st.simHandle, st.animListener of
    Just handle, Just listener | st.viewReady -> do
      ns <- liftEffect handle.getNodes
      liftEffect $ PacksView.renderPacksFrame
        { envLoc: Packs.envelopeLoc st.game.result.playerCount
        , nodes: ns
        , states: st.packStates
        , anim: st.packsAnim
        , hover: hoverPoss st
        , onHover: \k -> HS.notify listener (BubbleHovered k)
        }
    _, _ -> pure unit
  where
  -- packs dim only when the hover implicates at least one possibility
  hoverPoss st = case implicatedNow st of
    Just imp | not (Set.isEmpty imp.poss) -> Just imp.poss
    _ -> Nothing

-- | One frame of the packs: advance enter/exit progress, rebuild the
-- | bubbles. The loop keeps itself alive while the simulation is hot or
-- | anything is mid-flight.
packsAnimFrame :: forall m. MonadAff m => HostM m
packsAnimFrame = do
  st <- H.get
  case st.simHandle of
    Just handle -> do
      let anim = PacksView.tickPacksAnim enterDelta st.packsAnim
      H.modify_ _ { packsAnim = anim }
      drawPacksFrame
      alpha <- liftEffect handle.getAlpha
      when (alpha > 0.0015 || PacksView.packsAnimActive anim) scheduleAnimFrame
    Nothing -> pure unit

-- HATS owns everything under the view container; Halogen renders it
-- childless and never patches inside.
render :: forall m. State -> H.ComponentHTML Action () m
render st =
  HH.section [ HP.class_ (HH.ClassName "cascade-col") ]
    [ HH.div [ HP.class_ (HH.ClassName "cascade-toolbar") ]
        (if st.packView then packsLegend else gridLegend st)
    , HH.div [ HP.id (containerId st) ] []
    ]

-- | Legend for the possibility packs. No colour key — the table column's
-- | card chips carry the same category hues, so the mapping is learned
-- | from the ground truth itself.
packsLegend :: forall m. Array (H.ComponentHTML Action () m)
packsLegend =
  [ HH.span_ [ HH.text "faint = ruled out here" ]
  , HH.span_ [ HH.text "ring = located" ]
  , HH.span [ HP.class_ (HH.ClassName "legend-accent") ]
      [ HH.text "orbit = showed one of these" ]
  ]

gridLegend :: forall m. State -> Array (H.ComponentHTML Action () m)
gridLegend st =
  [ layoutButton st TableView "Table"
  , layoutButton st SkylineView "Skyline"
  , layoutButton st RadialView "Orbits"
  , HH.span [ HP.class_ (HH.ClassName "legend-sep") ] []
  , HH.span_ [ HH.text "● holds" ]
  , HH.span_ [ HH.text "× ruled out" ]
  , HH.span [ HP.class_ (HH.ClassName "legend-accent") ]
      [ HH.text "● in the envelope" ]
  , HH.span [ HP.class_ (HH.ClassName "legend-accent") ]
      [ HH.text "⌐ showed one of these" ]
  , HH.label [ HP.class_ (HH.ClassName "toggle") ]
      [ HH.input
          [ HP.type_ HP.InputCheckbox
          , HP.checked st.wiring
          , HE.onChecked ToggleWiring
          ]
      , HH.text "wiring"
      ]
  ]

layoutButton :: forall m. State -> GridLayout -> String -> H.ComponentHTML Action () m
layoutButton st l label =
  HH.button
    [ HP.classes
        ( map HH.ClassName
            (if st.gridLayout == l then [ "view-btn", "active" ] else [ "view-btn" ])
        )
    , HE.onClick \_ -> SetGridLayout l
    ]
    [ HH.text label ]
