-- | The cascade column as a child component — the one piece of the app
-- | that owns real resources: the HATS-managed SVG under `#cascade-view`,
-- | the force-simulation handle, and the requestAnimationFrame loop that
-- | drives both views' choreography. All of that lifecycle lives behind
-- | this boundary now; the parent just passes `{ game, position }` down
-- | and receives scrub intents back (sparkline bar clicks).
-- |
-- | `receive` is the seam: a position change reconciles the animation
-- | state against the fact diff (the scrub choreography); a genuinely
-- | different game — or a packs/grid switch, which is a controlled input
-- | so it survives remounts — tears the view down and rebuilds. The grid
-- | sub-toggles (wiring, DAG morph) are local state — no one outside
-- | this column cares.
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
import Data.Maybe (Maybe(..))
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
import Kibitzer.Frontend.Cascade.Anim (CascadeAnim, animActive, emptyAnim, enterDelta, syncAnim, tickAnim)
import Kibitzer.Frontend.Cascade.Scene (clearView, eventLabel, renderChrome)
import Kibitzer.Frontend.Cascade.View (redraw, stripFor, verdictFor)
import Kibitzer.Frontend.Packs.Model (PackRow, PossInfo)
import Kibitzer.Frontend.Packs.Model as Packs
import Kibitzer.Frontend.Packs.View (PacksAnim)
import Kibitzer.Frontend.Packs.View as PacksView
import Kibitzer.Frontend.Types (Game, currentEvent, currentKnowledge)
import Kibitzer.Knowledge (facts)
import Kibitzer.Player (playerCountToInt)

-- | `packView` arrives from the parent (controlled) so the Packs|Grid
-- | choice survives tab switches, which destroy and remount this
-- | component.
type Input = { game :: Game, position :: Int, packView :: Boolean }

data Output
  = ScrubRequested Int -- a sparkline bar click: the parent owns the timeline, we ask
  | ViewChanged Boolean -- the Packs|Grid buttons: the parent owns the choice, we ask

type Slot = H.Slot (Const Void) Output Unit

type State =
  { game :: Game
  , position :: Int
  , cascadeAnim :: CascadeAnim
  , animPending :: Boolean -- an animation frame is already scheduled
  , animListener :: Maybe (HS.Listener Action)
  , wiring :: Boolean -- keep settled provenance hairlines visible
  , dagView :: Boolean -- grid sub-view: morph the notebook into the derivation DAG
  , dagMorph :: Number -- 0 = table, 1 = DAG; animated between
  , packView :: Boolean -- mirror of the input; packs (true) or the grid
  , simHandle :: Maybe (SimulationHandle PackRow)
  , packStates :: Map Int PossInfo -- possibility states at the current position
  , packsAnim :: PacksAnim
  }

data Action
  = Initialize
  | Finalize
  | Receive Input
  | AnimTick
  | ToggleWiring Boolean
  | ToggleDag Boolean
  | SetPackView Boolean
  | BarClicked Int

component :: forall q m. MonadAff m => H.Component q Input Output m
component = H.mkComponent
  { initialState: \input ->
      { game: input.game
      , position: input.position
      , cascadeAnim: emptyAnim
      , animPending: false
      , animListener: Nothing
      , wiring: true
      , dagView: false
      , dagMorph: 0.0
      , packView: input.packView
      , simHandle: Nothing
      , packStates: Map.empty
      , packsAnim: PacksView.emptyPacksAnim
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
  Finalize -> stopPacksSim
  Receive input -> do
    st <- H.get
    H.modify_ _
      { game = input.game
      , position = input.position
      , packView = input.packView
      }
    if gameKey input.game /= gameKey st.game || input.packView /= st.packView then do
      -- a genuinely different deal, or a packs/grid switch: tear down
      -- and rebuild from scratch
      stopPacksSim
      initView
    else when (input.position /= st.position) do
      if st.packView then syncPacksMove
      else syncCascadeMove st.position input.position
  SetPackView b -> do
    st <- H.get
    when (b /= st.packView) (H.raise (ViewChanged b))
  -- one animation frame: advance progress, redraw, and keep the loop
  -- alive only while something is still moving
  AnimTick -> do
    H.modify_ _ { animPending = false }
    st <- H.get
    if st.packView then packsAnimFrame
    else do
      let
        target = if st.dagView then 1.0 else 0.0
        step = Tick.ticksForDuration 550
        morph
          | st.dagMorph < target = min target (st.dagMorph + step)
          | otherwise = max target (st.dagMorph - step)
        anim = tickAnim enterDelta st.cascadeAnim
      H.modify_ _ { cascadeAnim = anim, dagMorph = morph }
      redrawCascade
      when (animActive anim || morph /= target) scheduleAnimFrame
  ToggleWiring b -> do
    H.modify_ _ { wiring = b }
    redrawCascade
  -- the morph itself is animated by the frame loop; this just sets the target
  ToggleDag b -> do
    H.modify_ _ { dagView = b }
    scheduleAnimFrame
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
  H.liftAff (delay (Milliseconds 0.0))
  st <- H.get
  liftEffect clearView
  if st.packView then initPacks
  else do
    H.modify_ _
      { cascadeAnim = emptyAnim
      , dagMorph = if st.dagView then 1.0 else 0.0
      }
    liftEffect (renderChrome st.game.result.playerCount)
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
syncPacksMove :: forall m. MonadAff m => HostM m
syncPacksMove = do
  st <- H.get
  case st.simHandle of
    Nothing -> pure unit
    Just handle -> do
      let
        count = st.game.result.playerCount
        knowledge = currentKnowledge st.game st.position
        keep = Packs.survivorIds count knowledge
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
      _ <- liftEffect $ handle.updateData (kept <> fresh) []
      liftEffect $ handle.updateSetup (Packs.setupFor count (Packs.orbitSets knowledge))
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
      scheduleAnimFrame

-- | A timeline move while the grid is showing: reconcile the animation
-- | state with the fact diff, redraw, and (re)start the frame loop if
-- | anything is now in flight.
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
  redrawCascade
  when (animActive anim) scheduleAnimFrame

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

-- | Draw the grid's moving layers for the current state (chrome untouched).
redrawCascade :: forall m. MonadAff m => HostM m
redrawCascade = do
  st <- H.get
  case st.animListener of
    Just listener ->
      liftEffect $ redraw
        { game: st.game
        , position: st.position
        , wiring: st.wiring
        , morph: st.dagMorph
        , anim: st.cascadeAnim
        , onBar: \i -> HS.notify listener (BarClicked i)
        }
    Nothing -> pure unit

-- | The per-position layers of the packs view (orbit guides, rail,
-- | verdict, sparkline) — everything that changes on scrub but not
-- | per animation frame.
redrawPacksPosition :: forall m. MonadAff m => HostM m
redrawPacksPosition = do
  st <- H.get
  case st.animListener of
    Nothing -> pure unit
    Just listener ->
      liftEffect $ PacksView.renderPacksPosition
        { count: st.game.result.playerCount
        , orbits: Packs.orbitSets (currentKnowledge st.game st.position)
        , rail: eventLabel st.position (currentEvent st.game st.position)
        , verdict: verdictFor st.game st.position
        , strip: stripFor st.game st.position
        , onBar: \i -> HS.notify listener (BarClicked i)
        }

-- | One frame of the packs: advance enter/exit progress, read the live
-- | simulation positions, rebuild the bubbles. The loop keeps itself
-- | alive while the simulation is hot or anything is mid-flight.
packsAnimFrame :: forall m. MonadAff m => HostM m
packsAnimFrame = do
  st <- H.get
  case st.simHandle of
    Just handle -> do
      let anim = PacksView.tickPacksAnim enterDelta st.packsAnim
      H.modify_ _ { packsAnim = anim }
      ns <- liftEffect handle.getNodes
      liftEffect $ PacksView.renderPacksFrame
        { envLoc: Packs.envelopeLoc st.game.result.playerCount
        , nodes: ns
        , states: st.packStates
        , anim
        }
      alpha <- liftEffect handle.getAlpha
      when (alpha > 0.0015 || PacksView.packsAnimActive anim) scheduleAnimFrame
    Nothing -> pure unit

-- HATS owns everything under #cascade-view; Halogen renders it childless
-- and never patches inside.
render :: forall m. State -> H.ComponentHTML Action () m
render st =
  HH.section [ HP.class_ (HH.ClassName "cascade-col") ]
    [ HH.div [ HP.class_ (HH.ClassName "cascade-toolbar") ]
        ( [ viewButton st true "Packs"
          , viewButton st false "Grid"
          , HH.span [ HP.class_ (HH.ClassName "legend-sep") ] []
          ]
            <> (if st.packView then packsLegend else gridLegend st)
        )
    , HH.div [ HP.id "cascade-view" ] []
    ]

viewButton :: forall m. State -> Boolean -> String -> H.ComponentHTML Action () m
viewButton st packs label =
  HH.button
    [ HP.classes
        ( map HH.ClassName
            (if st.packView == packs then [ "view-btn", "active" ] else [ "view-btn" ])
        )
    , HE.onClick \_ -> SetPackView packs
    ]
    [ HH.text label ]

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
  [ HH.span_ [ HH.text "● holds" ]
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
  , HH.label [ HP.class_ (HH.ClassName "toggle") ]
      [ HH.input
          [ HP.type_ HP.InputCheckbox
          , HP.checked st.dagView
          , HE.onChecked ToggleDag
          ]
      , HH.text "DAG"
      ]
  ]
