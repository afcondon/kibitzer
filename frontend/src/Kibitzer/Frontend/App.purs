-- | The root component — now genuinely just the store. It owns the four
-- | things the whole app shares (the game, the timeline position, the
-- | play state, the current tab) plus the committed deal config; every
-- | resource-owning or reusable piece is a child component receiving that
-- | state as input and raising intents as output. The pedagogically
-- | interesting work all happens in kibitzer-core; this file is
-- | deliberately just plumbing.
-- |
-- | Children: `ControlPanel` (the deal form), `TransportBar` (play
-- | controls in the header), `CascadeHost` (the HATS/simulation/RAF
-- | column — the one with a real lifecycle). Pure panes stay pure
-- | functions.
module Kibitzer.Frontend.App (component) where

import Prelude

import Control.Monad.Rec.Class (forever)
import Data.Array as Array
import Data.Foldable (maximum)
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
import Halogen.Subscription as HS
import Kibitzer.Cascade (cascadeTimeline)
import Kibitzer.Frontend.Component.CascadeHost as CascadeHost
import Kibitzer.Frontend.Component.SeedControl as SeedControl
import Kibitzer.Frontend.Component.TransportBar as TransportBar
import Kibitzer.Frontend.Cascade.Layout (GridLayout(..))
import Kibitzer.Frontend.Crossref as Crossref
import Kibitzer.Frontend.Types (Discovery, Game, Tab(..), currentKnowledge, discoveries, maxPosition)
import Kibitzer.Frontend.View.Board (groundTruthPane)
import Kibitzer.Frontend.View.Terminal (terminalPane)
import Kibitzer.Cards (roomName, suspectName, weaponName)
import Kibitzer.Describe (describeFact)
import Kibitzer.Game (simulate)
import Kibitzer.Knowledge (Fact, FactId(..), envelopeIn, facts, solutionIfKnown)
import Data.Set (Set)
import Data.Set as Set
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Observe (Perspective(..))
import Kibitzer.Player (defaultPlayerCount, mkPlayerCount, playerCountToInt)
import Kibitzer.Policy (randomLegalPolicy)
import Kibitzer.Rng (mkSeed)
import Kibitzer.Track (positionsTimeline)
import Type.Proxy (Proxy(..))
import Web.HTML (window)
import Web.HTML.History (DocumentTitle(..), URL(..))
import Web.HTML.History as History
import Web.HTML.Location as Location
import Web.HTML.Window as Window

type Config = { seed :: Int, players :: Int, board :: Boolean }

type State =
  { config :: Config -- the committed deal, as last played
  , game :: Maybe Game
  , position :: Int
  , playing :: Boolean
  , tab :: Tab
  , hover :: Maybe Crossref.Hover -- the page-wide cross-reference hover
  , focused :: Maybe FactId -- the discovery stepper's current fact, if any
  }

data Action
  = Initialize
  | SetTab Tab
  | HandleSeed SeedControl.Output
  | HandleTransport TransportBar.Output
  | HandleCascade CascadeHost.Output
  | SetHover (Maybe Crossref.Hover)
  | Scrub Int
  | Tick

type Slots =
  ( seed :: SeedControl.Slot
  , transport :: TransportBar.Slot
  , packs :: CascadeHost.Slot
  , orbits :: CascadeHost.Slot
  , notebook :: CascadeHost.Slot
  )

_seed = Proxy :: Proxy "seed"
_transport = Proxy :: Proxy "transport"
_packs = Proxy :: Proxy "packs"
_orbits = Proxy :: Proxy "orbits"
_notebook = Proxy :: Proxy "notebook"

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: \_ ->
      { config: { seed: 42, players: 6, board: false }
      , game: Nothing
      , position: 0
      , playing: false
      , tab: PlayTab
      , hover: Nothing
      , focused: Nothing
      }
  , render
  , eval: H.mkEval (H.defaultEval { handleAction = handleAction, initialize = Just Initialize })
  }

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action Slots o m Unit
handleAction = case _ of
  Initialize -> do
    startTicker
    params <- liftEffect readParamsFromUrl
    startGame
      { seed: fromMaybe 42 params.seed
      , players: fromMaybe 6 params.players
      , board: false
      }
  SetTab tab -> H.modify_ _ { tab = tab, playing = false }
  HandleSeed output -> do
    config <- H.gets _.config
    case output of
      SeedControl.Committed n -> startGame config { seed = n }
      SeedControl.Rerolled -> do
        n <- liftEffect (randomInt 1 999999)
        startGame config { seed = n }
  HandleTransport output -> case output of
    TransportBar.Scrubbed n -> moveTo n
    TransportBar.PrevDiscovery -> stepDiscovery (-1)
    TransportBar.NextDiscovery -> stepDiscovery 1
    TransportBar.PlayToggled -> do
      st <- H.get
      let atEnd = map maxPosition st.game == Just st.position
      H.modify_ _ { playing = not st.playing, focused = Nothing }
      -- pressing play at the end restarts from the top
      when (not st.playing && atEnd) (moveTo 0)
  HandleCascade output -> case output of
    CascadeHost.ScrubRequested i -> moveTo i
    CascadeHost.HoverChanged h -> H.modify_ _ { hover = h }
  SetHover h -> H.modify_ _ { hover = h }
  Scrub n -> moveTo n
  Tick -> do
    st <- H.get
    case st.game of
      Just game | st.playing ->
        if st.position >= maxPosition game then H.modify_ _ { playing = false }
        else moveTo (st.position + 1)
      _ -> pure unit
  where
  -- any move that is not a discovery step drops the focus: the callout
  -- and its stepped highlight belong to the discovery cursor alone
  moveTo n = do
    st <- H.get
    case st.game of
      Nothing -> pure unit
      Just game -> H.modify_ _ { position = clamp 0 (maxPosition game) n, focused = Nothing }

  -- walk the deductive-fact index by `dir` (+1 next, -1 prev); landing on
  -- a discovery jumps the timeline to it and lights it via `focused`
  stepDiscovery dir = do
    st <- H.get
    case st.game of
      Nothing -> pure unit
      Just game -> case pickDiscovery (discoveries game) st.position st.focused dir of
        Nothing -> pure unit
        Just d -> H.modify_ _ { position = d.position, focused = Just d.factId, playing = false }

-- | The next/previous discovery from where the cursor sits. If a fact is
-- | already focused we move relative to it in the index; otherwise we jump
-- | to the first discovery beyond the current position in the step's
-- | direction (so scrubbing then stepping resumes sensibly).
pickDiscovery :: Array Discovery -> Int -> Maybe FactId -> Int -> Maybe Discovery
pickDiscovery discs position focused dir =
  case focused >>= \fid -> Array.findIndex (\d -> d.factId == fid) discs of
    Just i -> Array.index discs (i + dir)
    Nothing ->
      if dir > 0 then Array.find (\d -> d.position > position) discs
      else Array.last (Array.filter (\d -> d.position < position) discs)

startGame :: forall o m. MonadAff m => Config -> H.HalogenM State Action Slots o m Unit
startGame config = do
  let
    count = fromMaybe defaultPlayerCount (mkPlayerCount config.players)
    result = simulate
      { playerCount: count
      , seed: mkSeed config.seed
      , policy: randomLegalPolicy
      , maxTurns: 600
      , movement: config.board
      }
    snapshots = knowledgeTimeline count Watcher result.log
    positions = positionsTimeline count result.log
    cascades = cascadeTimeline count Watcher result.log
    depths = Map.unions (map _.depth cascades)
    allEdges = Array.concatMap _.edges cascades
  H.modify_ _
    { config = config { players = playerCountToInt count }
    , game = Just
        { seedInt: config.seed
        , movement: config.board
        , result
        , snapshots
        , positions
        , cascades
        , depths
        , allEdges
        }
    , position = 0
    , playing = false
    , focused = Nothing
    }
  liftEffect (writeParamsToUrl config.seed (playerCountToInt count))

-- | One global metronome; `Tick` decides whether anything moves. Simpler
-- | than subscribing and unsubscribing around play state.
startTicker :: forall o m. MonadAff m => H.HalogenM State Action Slots o m Unit
startTicker = do
  { emitter, listener } <- liftEffect HS.create
  void $ liftAff $ forkAff $ forever do
    delay (Milliseconds 700.0)
    liftEffect (HS.notify listener Tick)
  void (H.subscribe emitter)

readParamsFromUrl :: Effect { seed :: Maybe Int, players :: Maybe Int }
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
    }

writeParamsToUrl :: Int -> Int -> Effect Unit
writeParamsToUrl seedInt players = do
  history <- Window.history =<< window
  let
    url = "?seed=" <> show seedInt <> "&players=" <> show players
  History.pushState (unsafeToForeign {}) (DocumentTitle "kibitzer") (URL url) history

render :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
render st =
  HH.div [ HP.class_ (HH.ClassName "app") ]
    ([ header st ] <> floatBlock <> infoBar <> body)
  where
  -- a one-line strip under the header naming what the library on this
  -- page does. The Game page speaks for itself (the notebook is the
  -- library at work); the two engine pages get a caption.
  infoBar = case st.tab of
    BaskervilleTab ->
      [ infoBarEl "Baskerville amasses facts and deduces new ones from them — explaining every step of its reasoning." ]
    MycroftTab ->
      [ infoBarEl "Using the Z3 solver, Mycroft holds every solution still consistent with the facts it knows — whittling 44,460,928,512,000 possible deals down to just 1." ]
    PlayTab -> []

  infoBarEl txt =
    HH.div [ HP.class_ (HH.ClassName "info-bar") ] [ HH.text txt ]

  -- the transport drives the Game/Baskerville timeline; the Mycroft pane
  -- is a self-contained world-space view with its own stepping, and its
  -- seed is fixed, so the float (with its editable seed) is hidden there
  floatBlock = case st.tab of
    MycroftTab -> []
    _ -> case st.game of
      Just game -> [ floatingControls st game ]
      Nothing -> []

  body = case st.tab of
    MycroftTab ->
      [ HH.main [ HP.class_ (HH.ClassName "mycroft-pane") ]
          [ HH.iframe
              [ HP.src "worlds-768896.html"
              , HP.class_ (HH.ClassName "worlds-frame")
              , HP.title "Mycroft — the SMT world space"
              ]
          ]
      ]
    BaskervilleTab -> case st.game of
      Nothing -> [ HH.main_ [ HH.text "Dealing…" ] ]
      Just game ->
        -- two centred diagrams: the possibility packs collapsing on the
        -- left, the derivation DAG growing on the right, the current event
        -- captioned on the orbits. The packs take the *live* hover only —
        -- the discovery stepper's focus lights the DAG node, but must not
        -- fade the whole possibility space to its three implicated bubbles.
        [ HH.main [ HP.class_ (HH.ClassName "split2") ]
            [ HH.slot _packs unit CascadeHost.component
                { game, position: st.position, packView: true, layout: RadialView, hover: st.hover }
                HandleCascade
            , HH.slot _orbits unit CascadeHost.component
                { game, position: st.position, packView: false, layout: RadialView, hover: effectiveHover st }
                HandleCascade
            ]
        ]
    PlayTab -> case st.game of
      Nothing -> [ HH.main_ [ HH.text "Dealing…" ] ]
      Just game ->
        [ HH.main [ HP.class_ (HH.ClassName "split3-game") ]
            [ tableColumn st game
            , terminalPane terminalHover (hoverEvents st game) game st.position
            , HH.slot _notebook unit CascadeHost.component
                { game, position: st.position, packView: false, layout: TableView, hover: effectiveHover st }
                HandleCascade
            ]
        ]

-- | The floating control block, pinned top-right: seed reroll, the
-- | four-row transport, and — when the discovery stepper has a fact in
-- | focus — a callout naming exactly what was just worked out.
floatingControls :: forall m. MonadAff m => State -> Game -> H.ComponentHTML Action Slots m
floatingControls st game =
  HH.div [ HP.class_ (HH.ClassName "controls-float") ]
    ( [ HH.slot _seed unit SeedControl.component st.config.seed HandleSeed
      , HH.slot _transport unit TransportBar.component
          { position: st.position, max: maxPosition game, playing: st.playing }
          HandleTransport
      ]
        <> discoveryCallout st game
    )

-- | The sentence for the fact the discovery stepper is resting on — the
-- | `[E… · rule] …` line `describeFact` produces — shown without needing
-- | a mouse hover so a stepped deduction speaks for itself.
discoveryCallout :: forall m. State -> Game -> Array (H.ComponentHTML Action Slots m)
discoveryCallout st game = case focusedFact st game of
  Nothing -> []
  Just fact ->
    [ HH.div [ HP.class_ (HH.ClassName "discovery-callout") ]
        [ HH.text (describeFact fact) ]
    ]

-- | Resolve the focused fact id against what's visible at the current
-- | position.
focusedFact :: State -> Game -> Maybe Fact
focusedFact st game = do
  fid <- st.focused
  Array.find (\f -> f.id == fid) (facts (currentKnowledge game st.position))

-- | The single most-recent thing the watcher worked out, shown as a strip
-- | above the notebook grid — the old "how the watcher knows" feed
-- | distilled to its newest line.
latestDerivation :: forall m. Game -> Int -> H.ComponentHTML Action Slots m
latestDerivation game position =
  HH.div [ HP.class_ (HH.ClassName "latest-line") ]
    [ case Array.last (facts (currentKnowledge game position)) of
        Nothing ->
          HH.span [ HP.class_ (HH.ClassName "latest-empty") ]
            [ HH.text "The watcher hasn't inferred anything yet." ]
        Just fact -> HH.text (describeFact fact)
    ]

-- | The facts-per-event sparkline, moved up under the eye: a bar per event
-- | (height = facts inferred there), the current position in accent, each
-- | bar a scrub target. Labelled with the envelope progress / solution.
sparkline :: forall m. Game -> Int -> H.ComponentHTML Action Slots m
sparkline game position =
  HH.div [ HP.class_ (HH.ClassName "spark") ]
    [ HH.div [ HP.class_ (HH.ClassName "spark-label") ] [ HH.text label ]
    , HH.div [ HP.class_ (HH.ClassName "spark-bars") ]
        ( game.cascades # Array.mapWithIndex \i fr ->
            HH.div
              [ HP.classes
                  ( map HH.ClassName
                      (if i == position then [ "spark-bar", "current" ] else [ "spark-bar" ])
                  )
              , HP.style ("height:" <> show (barPct (Array.length fr.newFacts)) <> "%")
              , HP.title (if i == 0 then "start" else "E" <> show (i - 1))
              , HE.onClick \_ -> Scrub i
              ]
              []
        )
    ]
  where
  knowledge = currentKnowledge game position
  maxCount = fromMaybe 1 (maximum (map (Array.length <<< _.newFacts) game.cascades))
  barPct c = if c == 0 then 3.0 else max 8.0 (Int.toNumber c / Int.toNumber maxCount * 100.0)
  label = case solutionIfKnown knowledge of
    Just sol ->
      "Solved — " <> suspectName sol.suspect
        <> " · " <> weaponName sol.weapon
        <> " · " <> roomName sol.room
    Nothing -> "Envelope determined: " <> show (Set.size (envelopeIn knowledge)) <> " of 3"

-- | The highlight the page acts on: a live mouse hover wins; absent one,
-- | the discovery stepper's focused fact lights its own premise ancestry
-- | through the very same cross-reference path.
effectiveHover :: State -> Maybe Crossref.Hover
effectiveHover st = case st.hover of
  Just h -> Just h
  Nothing -> st.focused <#> \(FactId n) -> Crossref.HoverFact n

terminalHover :: { onEnter :: Int -> Action, onLeave :: Action }
terminalHover =
  { onEnter: \i -> SetHover (Just (Crossref.HoverEvent i))
  , onLeave: SetHover Nothing
  }

-- | The terminal lines implicated by the current highlight (hover or
-- | focused fact).
hoverEvents :: State -> Game -> Set Int
hoverEvents st game = case effectiveHover st of
  Nothing -> Set.empty
  Just h ->
    ( Crossref.implicated
        game.result.playerCount
        (facts (currentKnowledge game st.position))
        h
    ).events

-- | The left column: the deal controls above the ground truth.
tableColumn :: forall m. MonadAff m => State -> Game -> H.ComponentHTML Action Slots m
tableColumn st game =
  HH.div [ HP.class_ (HH.ClassName "table-col") ]
    [ groundTruthPane game st.position ]

header :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
header st =
  HH.header_
    [ HH.div [ HP.class_ (HH.ClassName "masthead") ]
        [ HH.h1_ [ HH.text "kibitzer" ]
        , HH.p [ HP.class_ (HH.ClassName "strap") ]
            [ HH.text "Two ways to deduce hidden facts — the PureScript libraries Baskerville and Mycroft." ]
        , HH.nav [ HP.class_ (HH.ClassName "tabs") ]
            [ tabButton st PlayTab "① Game"
            , tabButton st BaskervilleTab "② Baskerville"
            , tabButton st MycroftTab "③ Mycroft"
            ]
        ]
    , HH.div [ HP.class_ (HH.ClassName "header-center") ]
        ( [ HH.img
              [ HP.src "eye.svg"
              , HP.class_ (HH.ClassName "header-eye")
              , HP.alt "the watcher"
              ]
          ]
            -- the latest-line + sparkline track the app timeline; the
            -- Mycroft pane is a self-contained iframe, so only the eye
            -- carries over there
            <> case st.game of
                 Just game | st.tab /= MycroftTab ->
                   [ latestDerivation game st.position, sparkline game st.position ]
                 _ -> []
        )
    ]

tabButton :: forall m. MonadAff m => State -> Tab -> String -> H.ComponentHTML Action Slots m
tabButton st tab label =
  HH.button
    [ HP.classes
        (map HH.ClassName (if st.tab == tab then [ "tab", "active" ] else [ "tab" ]))
    , HE.onClick \_ -> SetTab tab
    ]
    [ HH.text label ]
