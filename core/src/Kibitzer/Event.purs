-- | The ground-truth event log. `simulate` produces one of these; every
-- | view of the game — each player's, and crucially the watcher's — is a
-- | projection of it (see `Kibitzer.Observe`).
-- |
-- | `Passed` and `CardShown` carry the suggestion they answer. That is a
-- | deliberate denormalisation: it keeps `learn` context-free, with no
-- | learner-side state machine tracking "the suggestion in play".
module Kibitzer.Event
  ( EventId(..)
  , eventIdToInt
  , Event(..)
  , Log
  ) where

import Prelude

import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Set (Set)
import Data.Show.Generic (genericShow)
import Kibitzer.Board (Position)
import Kibitzer.Cards (Card)
import Kibitzer.Player (PlayerCount, PlayerId)
import Kibitzer.Suggestion (Solution, Suggestion)

newtype EventId = EventId Int

derive instance Eq EventId
derive instance Ord EventId

instance Show EventId where
  show (EventId i) = "(EventId " <> show i <> ")"

eventIdToInt :: EventId -> Int
eventIdToInt (EventId i) = i

data Event
  = GameDealt { players :: PlayerCount, hands :: Map PlayerId (Set Card), solution :: Solution }
  | Moved { player :: PlayerId, roll :: Int, position :: Position }
  | SuggestionMade { by :: PlayerId, suggestion :: Suggestion }
  | Passed { player :: PlayerId, suggestion :: Suggestion }
  | CardShown { by :: PlayerId, to :: PlayerId, card :: Card, suggestion :: Suggestion }
  | AccusationMade { by :: PlayerId, accusation :: Suggestion, correct :: Boolean }

derive instance Eq Event
derive instance Generic Event _

instance Show Event where
  show = genericShow

type Log = Array Event
