-- | The root (and only) component. Plain `H.mkComponent`, no hooks:
-- | one lump of state, pure render helpers per pane, and a handful of
-- | actions. The pedagogically interesting work all happens in
-- | kibitzer-core; this file is deliberately just plumbing.
module Kibitzer.Frontend.App (component) where

import Prelude

import Control.Monad.Rec.Class (forever)
import Data.Array as Array
import Data.Int as Int
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..))
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Aff (delay, forkAff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Effect.Random (randomInt)
import Foreign (unsafeToForeign)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Data.Set as Set
import Halogen.Subscription as HS
import Hylograph.Simulation (Engine(..), runSimulation)
import Hylograph.Transition.RAF as RAF
import Hylograph.Transition.Tick as Tick
import Kibitzer.Cascade (cascadeTimeline)
import Kibitzer.Frontend.Cascade.Anim (animActive, emptyAnim, enterDelta, syncAnim, tickAnim)
import Kibitzer.Frontend.Cascade.Scene (clearView, eventLabel, renderChrome)
import Kibitzer.Frontend.Cascade.View (redraw, stripFor, verdictFor)
import Kibitzer.Frontend.Packs.Model as Packs
import Kibitzer.Frontend.Packs.View as PacksView
import Kibitzer.Frontend.Types (Action(..), Game, State, Tab(..), currentEvent, currentKnowledge, maxPosition)
import Kibitzer.Frontend.View.About (aboutPage)
import Kibitzer.Frontend.View.Board (boardPane)
import Kibitzer.Frontend.View.Code (codePage)
import Kibitzer.Frontend.View.Feed (feedPane)
import Kibitzer.Frontend.View.Notebook (notebookPane)
import Kibitzer.Frontend.View.Terminal (terminalPane)
import Kibitzer.Frontend.View.Timeline (transportBar)
import Kibitzer.Game (simulate)
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (facts)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (defaultPlayerCount, mkPlayerCount, playerCountToInt)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Track (positionsTimeline)
import Web.HTML (window)
import Web.HTML.History (DocumentTitle(..), URL(..))
import Web.HTML.History as History
import Web.HTML.Location as Location
import Web.HTML.Window as Window

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: \_ ->
      { seedInput: "42"
      , playersInput: 4
      , movesInput: false
      , game: Nothing
      , position: 0
      , playing: false
      , tab: PlayTab
      , cascadeAnim: emptyAnim
      , animPending: false
      , animListener: Nothing
      , wiring: true
      , packView: true
      , simHandle: Nothing
      , packStates: Map.empty
      , packsAnim: PacksView.emptyPacksAnim
      }
  , render
  , eval: H.mkEval (H.defaultEval { handleAction = handleAction, initialize = Just Initialize })
  }

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  Initialize -> do
    startTicker
    -- the cascade's animation-frame channel: RAF callbacks notify
    -- AnimTick through here, back into ordinary Halogen evaluation
    { emitter, listener } <- liftEffect HS.create
    void (H.subscribe emitter)
    H.modify_ _ { animListener = Just listener }
    params <- liftEffect readParamsFromUrl
    H.modify_ _
      { playersInput = fromMaybe 4 params.players
      , movesInput = params.moves
      }
    startGame (fromMaybe 42 params.seed)
  SetTab tab -> do
    stopPacksSim
    H.modify_ _ { tab = tab, playing = false }
    when (tab == CascadeTab) initCascadeView
  SetPackView b -> do
    st <- H.get
    when (b /= st.packView) do
      stopPacksSim
      H.modify_ _ { packView = b }
      initCascadeView
  SetSeedInput s -> H.modify_ _ { seedInput = s }
  -- table-shape changes re-deal at once with the same seed
  SetPlayers s -> do
    case Int.fromString s of
      Just n -> do
        H.modify_ _ { playersInput = n }
        restartSameSeed
      Nothing -> pure unit
  ToggleMoves b -> do
    H.modify_ _ { movesInput = b }
    restartSameSeed
  NewGame -> restartSameSeed
  RandomSeed -> do
    n <- liftEffect (randomInt 1 999999)
    startGame n
  Scrub n -> moveTo n
  StepBack -> H.gets _.position >>= \p -> moveTo (p - 1)
  StepForward -> H.gets _.position >>= \p -> moveTo (p + 1)
  JumpStart -> moveTo 0
  JumpEnd -> H.gets _.game >>= case _ of
    Just game -> moveTo (maxPosition game)
    Nothing -> pure unit
  TogglePlay -> do
    st <- H.get
    let atEnd = map maxPosition st.game == Just st.position
    H.modify_ _ { playing = not st.playing }
    -- pressing play at the end restarts from the top
    when (not st.playing && atEnd) (moveTo 0)
  Tick -> do
    st <- H.get
    case st.game of
      Just game | st.playing ->
        if st.position >= maxPosition game then H.modify_ _ { playing = false }
        else moveTo (st.position + 1)
      _ -> pure unit
  -- one animation frame: advance progress, redraw, and keep the loop
  -- alive only while something is still moving
  AnimTick -> do
    H.modify_ _ { animPending = false }
    st <- H.get
    when (st.tab == CascadeTab) do
      if st.packView then packsAnimFrame
      else do
        let anim = tickAnim enterDelta st.cascadeAnim
        H.modify_ _ { cascadeAnim = anim }
        redrawCascade
        when (animActive anim) scheduleAnimFrame
  ToggleWiring b -> do
    H.modify_ _ { wiring = b }
    redrawCascade
  where
  moveTo n = do
    st <- H.get
    case st.game of
      Nothing -> pure unit
      Just game -> do
        let new = clamp 0 (maxPosition game) n
        H.modify_ _ { position = new }
        when (st.tab == CascadeTab && new /= st.position) do
          if st.packView then syncPacksMove game new
          else syncCascadeMove game st.position new

-- | A timeline move while the cascade is showing: reconcile the
-- | animation state with the fact diff, redraw, and (re)start the frame
-- | loop if anything is now in flight.
syncCascadeMove :: forall o m. MonadAff m => Game -> Int -> Int -> H.HalogenM State Action () o m Unit
syncCascadeMove game oldPos newPos = do
  st <- H.get
  let
    count = game.result.playerCount
    anim = syncAnim count game.depths
      (facts (currentKnowledge game oldPos))
      (facts (currentKnowledge game newPos))
      st.cascadeAnim
  H.modify_ _ { cascadeAnim = anim }
  redrawCascade
  when (animActive anim) scheduleAnimFrame

-- | Schedule exactly one animation frame; its callback re-enters Halogen
-- | as AnimTick. Self-perpetuating while animations are active — this is
-- | the whole RAF→Halogen bridge.
scheduleAnimFrame :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
scheduleAnimFrame = do
  st <- H.get
  case st.animListener of
    Just listener | not st.animPending -> do
      H.modify_ _ { animPending = true }
      void $ liftEffect $ RAF.requestAnimationFrame \_ -> HS.notify listener AnimTick
    _ -> pure unit

-- | Draw the moving layers for the current state (chrome untouched).
redrawCascade :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
redrawCascade = do
  st <- H.get
  case st.game, st.animListener of
    Just game, Just listener | st.tab == CascadeTab ->
      liftEffect $ redraw
        { game
        , position: st.position
        , wiring: st.wiring
        , anim: st.cascadeAnim
        , onBar: \i -> HS.notify listener (Scrub i)
        }
    _, _ -> pure unit

-- | Entering the cascade tab (or re-dealing while on it): wait a beat for
-- | Halogen to have mounted the empty container, then draw chrome and the
-- | current position from scratch — packs or grid, whichever is chosen.
initCascadeView :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
initCascadeView = do
  H.liftAff (delay (Milliseconds 0.0))
  st <- H.get
  case st.game of
    Nothing -> pure unit
    Just game -> do
      liftEffect clearView
      if st.packView then initPacks game
      else do
        H.modify_ _ { cascadeAnim = emptyAnim }
        liftEffect (renderChrome game.result.playerCount)
        redrawCascade

-- | Fresh simulation for the possibility packs: chrome, the survivors at
-- | the current position, orbit forces for the live disjunctions.
initPacks :: forall o m. MonadAff m => Game -> H.HalogenM State Action () o m Unit
initPacks game = do
  stopPacksSim
  st <- H.get
  let
    count = game.result.playerCount
    knowledge = currentKnowledge game st.position
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
  redrawPacksPosition game
  scheduleAnimFrame

stopPacksSim :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
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
syncPacksMove :: forall o m. MonadAff m => Game -> Int -> H.HalogenM State Action () o m Unit
syncPacksMove game newPos = do
  st <- H.get
  case st.simHandle of
    Nothing -> pure unit
    Just handle -> do
      let
        count = game.result.playerCount
        knowledge = currentKnowledge game newPos
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
      redrawPacksPosition game
      scheduleAnimFrame

-- | The per-position layers of the packs view (orbit guides, rail,
-- | verdict, sparkline) — everything that changes on scrub but not
-- | per animation frame.
redrawPacksPosition :: forall o m. MonadAff m => Game -> H.HalogenM State Action () o m Unit
redrawPacksPosition game = do
  st <- H.get
  case st.animListener of
    Nothing -> pure unit
    Just listener ->
      liftEffect $ PacksView.renderPacksPosition
        { count: game.result.playerCount
        , orbits: Packs.orbitSets (currentKnowledge game st.position)
        , rail: eventLabel st.position (currentEvent game st.position)
        , verdict: verdictFor game st.position
        , strip: stripFor game st.position
        , onBar: \i -> HS.notify listener (Scrub i)
        }

-- | One frame of the packs: advance enter/exit progress, read the live
-- | simulation positions, rebuild the bubbles. The loop keeps itself
-- | alive while the simulation is hot or anything is mid-flight.
packsAnimFrame :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
packsAnimFrame = do
  st <- H.get
  case st.game, st.simHandle of
    Just game, Just handle -> do
      let anim = PacksView.tickPacksAnim enterDelta st.packsAnim
      H.modify_ _ { packsAnim = anim }
      ns <- liftEffect handle.getNodes
      liftEffect $ PacksView.renderPacksFrame
        { envLoc: Packs.envelopeLoc game.result.playerCount
        , nodes: ns
        , states: st.packStates
        , anim
        }
      alpha <- liftEffect handle.getAlpha
      when (alpha > 0.0015 || PacksView.packsAnimActive anim) scheduleAnimFrame
    _, _ -> pure unit

restartSameSeed :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
restartSameSeed = do
  input <- H.gets _.seedInput
  case Int.fromString (String.trim input) of
    Just n -> startGame n
    Nothing -> pure unit

startGame :: forall o m. MonadAff m => Int -> H.HalogenM State Action () o m Unit
startGame seedInt = do
  st <- H.get
  let
    count = fromMaybe defaultPlayerCount (mkPlayerCount st.playersInput)
    result = simulate
      { playerCount: count
      , seed: mkSeed seedInt
      , policy: randomLegalPolicy
      , maxTurns: 600
      , movement: st.movesInput
      }
    snapshots = knowledgeTimeline count Watcher result.log
    positions = positionsTimeline count result.log
    cascades = cascadeTimeline count Watcher result.log
    depths = Map.unions (map _.depth cascades)
    allEdges = Array.concatMap _.edges cascades
  H.modify_ _
    { game = Just { seedInt, result, snapshots, positions, cascades, depths, allEdges }
    , position = 0
    , playing = false
    , seedInput = show seedInt
    , cascadeAnim = emptyAnim
    }
  liftEffect (writeParamsToUrl seedInt (playerCountToInt count) st.movesInput)
  when (st.tab == CascadeTab) initCascadeView

-- | One global metronome; `Tick` decides whether anything moves. Simpler
-- | than subscribing and unsubscribing around play state.
startTicker :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
startTicker = do
  { emitter, listener } <- liftEffect HS.create
  void $ liftAff $ forkAff $ forever do
    delay (Milliseconds 700.0)
    liftEffect (HS.notify listener Tick)
  void (H.subscribe emitter)

readParamsFromUrl :: Effect { seed :: Maybe Int, players :: Maybe Int, moves :: Boolean }
readParamsFromUrl = do
  search <- Location.search =<< Window.location =<< window
  let
    params = String.split (Pattern "&") (fromMaybe search (String.stripPrefix (Pattern "?") search))
    intParam name = Array.findMap
      (\p -> Int.fromString =<< String.stripPrefix (Pattern (name <> "=")) p)
      params
  pure
    { seed: intParam "seed"
    , players: intParam "players"
    , moves: intParam "moves" == Just 1
    }

writeParamsToUrl :: Int -> Int -> Boolean -> Effect Unit
writeParamsToUrl seedInt players moves = do
  history <- Window.history =<< window
  let
    url = "?seed=" <> show seedInt
      <> "&players=" <> show players
      <> (if moves then "&moves=1" else "")
  History.pushState (unsafeToForeign {}) (DocumentTitle "kibitzer") (URL url) history

render :: forall m. State -> H.ComponentHTML Action () m
render st =
  HH.div [ HP.class_ (HH.ClassName "app") ]
    case st.tab of
      AboutTab -> [ header st, aboutPage ]
      CodeTab -> [ header st, codePage ]
      -- HATS owns everything under #cascade-view; Halogen renders it
      -- childless and never patches inside
      CascadeTab ->
        [ header st
        , case st.game of
            Nothing -> HH.main_ [ HH.text "Dealing…" ]
            Just game ->
              HH.main [ HP.class_ (HH.ClassName "split3") ]
                [ tableColumn st game
                , terminalPane game st.position
                , HH.section [ HP.class_ (HH.ClassName "cascade-col") ]
                    [ HH.div [ HP.class_ (HH.ClassName "cascade-toolbar") ]
                        ( [ viewButton st true "Packs"
                          , viewButton st false "Grid"
                          , HH.span [ HP.class_ (HH.ClassName "legend-sep") ] []
                          ]
                            <> (if st.packView then packsLegend else gridLegend st)
                        )
                    , HH.div [ HP.id "cascade-view" ] []
                    ]
                ]
        ]
      PlayTab ->
        [ header st
        , case st.game of
            Nothing -> HH.main_ [ HH.text "Dealing…" ]
            Just game ->
              HH.main [ HP.class_ (HH.ClassName "split3") ]
                [ tableColumn st game
                , terminalPane game st.position
                , HH.div [ HP.class_ (HH.ClassName "watcher-pane") ]
                    [ notebookPane game st.position
                    , feedPane game st.position
                    ]
                ]
        ]

-- | The left column: the game's own controls above the ground truth.
tableColumn :: forall m. State -> Game -> H.ComponentHTML Action () m
tableColumn st game =
  HH.div [ HP.class_ (HH.ClassName "table-col") ]
    [ HH.div [ HP.class_ (HH.ClassName "controls") ]
        [ HH.label_ [ HH.text "Seed" ]
        , HH.input
            [ HP.value st.seedInput
            , HP.type_ HP.InputText
            , HE.onValueInput SetSeedInput
            ]
        , HH.label_ [ HH.text "Players" ]
        , HH.select [ HE.onValueChange SetPlayers ]
            ( map
                ( \n -> HH.option
                    [ HP.value (show n), HP.selected (n == st.playersInput) ]
                    [ HH.text (show n) ]
                )
                [ 3, 4, 5, 6 ]
            )
        , HH.label [ HP.class_ (HH.ClassName "toggle") ]
            [ HH.input
                [ HP.type_ HP.InputCheckbox
                , HP.checked st.movesInput
                , HE.onChecked ToggleMoves
                ]
            , HH.text "Board"
            ]
        , HH.button [ HE.onClick \_ -> NewGame ] [ HH.text "Deal" ]
        , HH.button [ HE.onClick \_ -> RandomSeed ] [ HH.text "Random" ]
        ]
    , boardPane game st.position
    ]

header :: forall m. State -> H.ComponentHTML Action () m
header st =
  HH.header_
    [ HH.div [ HP.class_ (HH.ClassName "masthead") ]
        [ HH.h1_ [ HH.text "kibitzer" ]
        , HH.p [ HP.class_ (HH.ClassName "strap") ]
            [ HH.text "A Cluedo watcher who never sees a card — and solves the murder from metadata alone." ]
        , HH.nav [ HP.class_ (HH.ClassName "tabs") ]
            [ tabButton st PlayTab "Game"
            , tabButton st CascadeTab "Cascade"
            , tabButton st AboutTab "About"
            , tabButton st CodeTab "The code"
            ]
        ]
    , case st.game of
        Just game -> transportBar game st.position st.playing
        Nothing -> HH.text ""
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
  ]

tabButton :: forall m. State -> Tab -> String -> H.ComponentHTML Action () m
tabButton st tab label =
  HH.button
    [ HP.classes
        (map HH.ClassName (if st.tab == tab then [ "tab", "active" ] else [ "tab" ]))
    , HE.onClick \_ -> SetTab tab
    ]
    [ HH.text label ]

