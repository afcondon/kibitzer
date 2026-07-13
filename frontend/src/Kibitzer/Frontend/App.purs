-- | The root (and only) component. Plain `H.mkComponent`, no hooks:
-- | one lump of state, pure render helpers per pane, and a handful of
-- | actions. The pedagogically interesting work all happens in
-- | kibitzer-core; this file is deliberately just plumbing.
module Kibitzer.Frontend.App (component) where

import Prelude

import Control.Monad.Rec.Class (forever)
import Data.Array as Array
import Data.Int as Int
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
import Kibitzer.Frontend.Types (Action(..), State, Tab(..), currentKnowledge, maxPosition)
import Kibitzer.Frontend.View.About (aboutPage)
import Kibitzer.Frontend.View.Board (boardPane)
import Kibitzer.Frontend.View.Code (codePage)
import Kibitzer.Frontend.View.Feed (feedPane)
import Kibitzer.Frontend.View.Notebook (notebookPane)
import Kibitzer.Frontend.View.Timeline (timelinePane)
import Kibitzer.Game (simulate)
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (factCount)
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
      }
  , render
  , eval: H.mkEval (H.defaultEval { handleAction = handleAction, initialize = Just Initialize })
  }

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  Initialize -> do
    startTicker
    params <- liftEffect readParamsFromUrl
    H.modify_ _
      { playersInput = fromMaybe 4 params.players
      , movesInput = params.moves
      }
    startGame (fromMaybe 42 params.seed)
  SetTab tab -> H.modify_ _ { tab = tab, playing = false }
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
    -- pressing play at the end restarts from the top
    H.modify_ _
      { playing = not st.playing
      , position = if not st.playing && atEnd then 0 else st.position
      }
  Tick -> do
    st <- H.get
    case st.game of
      Just game | st.playing ->
        if st.position >= maxPosition game then H.modify_ _ { playing = false }
        else H.modify_ _ { position = st.position + 1 }
      _ -> pure unit
  where
  moveTo n = do
    st <- H.get
    case st.game of
      Nothing -> pure unit
      Just game -> H.modify_ _ { position = clamp 0 (maxPosition game) n }

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
  H.modify_ _
    { game = Just { seedInt, result, snapshots, positions }
    , position = 0
    , playing = false
    , seedInput = show seedInt
    }
  liftEffect (writeParamsToUrl seedInt (playerCountToInt count) st.movesInput)

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
      PlayTab ->
        [ header st
        , case st.game of
            Nothing -> HH.main_ [ HH.text "Dealing…" ]
            Just game ->
              HH.main [ HP.class_ (HH.ClassName "split") ]
                [ boardPane game st.position
                , HH.div [ HP.class_ (HH.ClassName "watcher-pane") ]
                    [ notebookPane game st.position
                    , feedPane game st.position
                    ]
                ]
        , case st.game of
            Nothing -> HH.text ""
            Just game -> timelinePane game st.position st.playing
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
            , tabButton st AboutTab "About"
            , tabButton st CodeTab "The code"
            ]
        ]
    , HH.div [ HP.class_ (HH.ClassName "counter") ] (counter st)
    , HH.div [ HP.class_ (HH.ClassName "controls") ]
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
    ]

tabButton :: forall m. State -> Tab -> String -> H.ComponentHTML Action () m
tabButton st tab label =
  HH.button
    [ HP.classes
        (map HH.ClassName (if st.tab == tab then [ "tab", "active" ] else [ "tab" ]))
    , HE.onClick \_ -> SetTab tab
    ]
    [ HH.text label ]

counter :: forall m. State -> Array (H.ComponentHTML Action () m)
counter st = case st.game of
  Nothing -> []
  Just game ->
    [ HH.div [ HP.class_ (HH.ClassName "stat") ]
        [ HH.span [ HP.class_ (HH.ClassName "stat-number") ] [ HH.text "0" ]
        , HH.span [ HP.class_ (HH.ClassName "stat-label") ] [ HH.text "cards seen" ]
        ]
    , HH.div [ HP.class_ (HH.ClassName "stat accent") ]
        [ HH.span [ HP.class_ (HH.ClassName "stat-number") ]
            [ HH.text (show (factCount (currentKnowledge game st.position))) ]
        , HH.span [ HP.class_ (HH.ClassName "stat-label") ] [ HH.text "facts inferred" ]
        ]
    ]
