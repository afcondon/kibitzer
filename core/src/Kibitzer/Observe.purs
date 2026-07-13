-- | Perspectives, and the projection of ground truth onto each of them.
-- | This one function *is* the privacy model of the whole demo:
-- |
-- |   * the `Watcher` never sees a hand and never sees a shown card —
-- |     only that *some* card changed hands;
-- |   * a player additionally sees their own dealt hand, and the identity
-- |     of a shown card exactly when they showed it or were shown it.
-- |
-- | A player is therefore just a watcher with extra private observations.
-- | Everything else in the codebase treats the two identically.
module Kibitzer.Observe
  ( Perspective(..)
  , Observation(..)
  , observe
  , observeLog
  ) where

import Prelude

import Data.Array (mapWithIndex)
import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Show.Generic (genericShow)
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card)
import Kibitzer.Event (Event(..), EventId(..), Log)
import Kibitzer.Player (PlayerCount, PlayerId)
import Kibitzer.Suggestion (Suggestion)

data Perspective = Watcher | PlayerView PlayerId

derive instance Eq Perspective
derive instance Generic Perspective _

instance Show Perspective where
  show = genericShow

data Observation
  = ObsDealt
      { players :: PlayerCount
      , handSizes :: Map PlayerId Int
      , ownHand :: Maybe { player :: PlayerId, hand :: Set Card }
      }
  | ObsSuggestion { by :: PlayerId, suggestion :: Suggestion }
  | ObsPassed { player :: PlayerId, suggestion :: Suggestion }
  | ObsShowed { by :: PlayerId, to :: PlayerId, suggestion :: Suggestion, card :: Maybe Card }
  | ObsAccused { by :: PlayerId, accusation :: Suggestion, correct :: Boolean }

derive instance Eq Observation
derive instance Generic Observation _

instance Show Observation where
  show = genericShow

observe :: Perspective -> Event -> Observation
observe perspective = case _ of
  GameDealt { players, hands } ->
    ObsDealt
      { players
      , handSizes: map Set.size hands
      , ownHand: case perspective of
          Watcher -> Nothing
          PlayerView p -> map (\hand -> { player: p, hand }) (Map.lookup p hands)
      }
  SuggestionMade s -> ObsSuggestion s
  Passed p -> ObsPassed p
  CardShown { by, to, card, suggestion } ->
    ObsShowed
      { by
      , to
      , suggestion
      , card: case perspective of
          Watcher -> Nothing
          PlayerView p -> if p == by || p == to then Just card else Nothing
      }
  AccusationMade a -> ObsAccused a

observeLog :: Perspective -> Log -> Array (Tuple EventId Observation)
observeLog perspective = mapWithIndex \i event -> Tuple (EventId i) (observe perspective event)
