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
import Kibitzer.Frontend.Component.ControlPanel as ControlPanel
import Kibitzer.Frontend.Component.SeedControl as SeedControl
import Kibitzer.Frontend.Component.TransportBar as TransportBar
import Kibitzer.Frontend.Crossref as Crossref
import Kibitzer.Frontend.Types (Game, Tab(..), currentKnowledge, maxPosition)
import Kibitzer.Frontend.View.About (aboutPage)
import Kibitzer.Frontend.View.Board (boardPane)
import Kibitzer.Frontend.View.Code (codePage)
import Kibitzer.Frontend.View.Feed (feedPane)
import Kibitzer.Frontend.View.Notebook (notebookPane)
import Kibitzer.Frontend.View.Terminal (terminalPane)
import Kibitzer.Game (simulate)
import Kibitzer.Knowledge (facts)
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
  }

data Action
  = Initialize
  | SetTab Tab
  | HandleControls ControlPanel.Output
  | HandleSeed SeedControl.Output
  | HandleTransport TransportBar.Output
  | HandleCascade CascadeHost.Output
  | SetHover (Maybe Crossref.Hover)
  | Tick

type Slots =
  ( controls :: ControlPanel.Slot
  , seed :: SeedControl.Slot
  , transport :: TransportBar.Slot
  , packs :: CascadeHost.Slot
  , orbits :: CascadeHost.Slot
  )

_controls = Proxy :: Proxy "controls"
_seed = Proxy :: Proxy "seed"
_transport = Proxy :: Proxy "transport"
_packs = Proxy :: Proxy "packs"
_orbits = Proxy :: Proxy "orbits"

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: \_ ->
      { config: { seed: 42, players: 4, board: false }
      , game: Nothing
      , position: 0
      , playing: false
      , tab: PlayTab
      , hover: Nothing
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
      , players: fromMaybe 4 params.players
      , board: params.moves
      }
  SetTab tab -> H.modify_ _ { tab = tab, playing = false }
  HandleControls output -> do
    config <- H.gets _.config
    case output of
      ControlPanel.PlayersChanged n -> startGame config { players = n }
      ControlPanel.BoardToggled b -> startGame config { board = b }
  HandleSeed output -> do
    config <- H.gets _.config
    case output of
      SeedControl.Committed n -> startGame config { seed = n }
      SeedControl.Rerolled -> do
        n <- liftEffect (randomInt 1 999999)
        startGame config { seed = n }
  HandleTransport output -> case output of
    TransportBar.Scrubbed n -> moveTo n
    TransportBar.PlayToggled -> do
      st <- H.get
      let atEnd = map maxPosition st.game == Just st.position
      H.modify_ _ { playing = not st.playing }
      -- pressing play at the end restarts from the top
      when (not st.playing && atEnd) (moveTo 0)
  HandleCascade output -> case output of
    CascadeHost.ScrubRequested i -> moveTo i
    CascadeHost.HoverChanged h -> H.modify_ _ { hover = h }
  SetHover h -> H.modify_ _ { hover = h }
  Tick -> do
    st <- H.get
    case st.game of
      Just game | st.playing ->
        if st.position >= maxPosition game then H.modify_ _ { playing = false }
        else moveTo (st.position + 1)
      _ -> pure unit
  where
  moveTo n = do
    st <- H.get
    case st.game of
      Nothing -> pure unit
      Just game -> H.modify_ _ { position = clamp 0 (maxPosition game) n }

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
    }
  liftEffect (writeParamsToUrl config.seed (playerCountToInt count) config.board)

-- | One global metronome; `Tick` decides whether anything moves. Simpler
-- | than subscribing and unsubscribing around play state.
startTicker :: forall o m. MonadAff m => H.HalogenM State Action Slots o m Unit
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

render :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
render st =
  HH.div [ HP.class_ (HH.ClassName "app") ]
    case st.tab of
      AboutTab -> [ header st, aboutPage ]
      CodeTab -> [ header st, codePage ]
      CascadeTab ->
        [ header st
        , case st.game of
            Nothing -> HH.main_ [ HH.text "Dealing…" ]
            Just game ->
              HH.main [ HP.classes (map HH.ClassName [ "split3", "crossref" ]) ]
                [ HH.slot _packs unit CascadeHost.component
                    { game, position: st.position, packView: true, hover: st.hover }
                    HandleCascade
                , terminalPane terminalHover (hoverEvents st game) game st.position
                , HH.slot _orbits unit CascadeHost.component
                    { game, position: st.position, packView: false, hover: st.hover }
                    HandleCascade
                ]
        ]
      PlayTab ->
        [ header st
        , case st.game of
            Nothing -> HH.main_ [ HH.text "Dealing…" ]
            Just game ->
              HH.main [ HP.class_ (HH.ClassName "split4") ]
                [ tableColumn st game
                , terminalPane terminalHover (hoverEvents st game) game st.position
                , HH.div [ HP.class_ (HH.ClassName "watcher-pane") ]
                    [ notebookPane game st.position ]
                , HH.div [ HP.classes (map HH.ClassName [ "watcher-pane", "feed-col" ]) ]
                    [ feedPane game st.position ]
                ]
        ]

terminalHover :: { onEnter :: Int -> Action, onLeave :: Action }
terminalHover =
  { onEnter: \i -> SetHover (Just (Crossref.HoverEvent i))
  , onLeave: SetHover Nothing
  }

-- | The terminal lines implicated by the current hover.
hoverEvents :: State -> Game -> Set Int
hoverEvents st game = case st.hover of
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
    [ HH.slot _controls unit ControlPanel.component
        { players: st.config.players, board: st.config.board }
        HandleControls
    , boardPane game st.position
    ]

header :: forall m. MonadAff m => State -> H.ComponentHTML Action Slots m
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
        Just game ->
          HH.div [ HP.class_ (HH.ClassName "transport-cell") ]
            [ HH.slot _seed unit SeedControl.component st.config.seed HandleSeed
            , HH.slot _transport unit TransportBar.component
                { position: st.position, max: maxPosition game, playing: st.playing }
                HandleTransport
            ]
        Nothing -> HH.text ""
    ]

tabButton :: forall m. MonadAff m => State -> Tab -> String -> H.ComponentHTML Action Slots m
tabButton st tab label =
  HH.button
    [ HP.classes
        (map HH.ClassName (if st.tab == tab then [ "tab", "active" ] else [ "tab" ]))
    , HE.onClick \_ -> SetTab tab
    ]
    [ HH.text label ]
