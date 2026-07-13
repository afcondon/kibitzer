-- | Prose for events, claims, and facts — shared by the CLI transcript
-- | and the web frontend's derivation feed. Pure string assembly.
module Kibitzer.Describe
  ( playerName
  , cardPhrase
  , describeSuggestion
  , describeEvent
  , describeClaim
  , describeFact
  , ruleName
  , eventRef
  ) where

import Prelude

import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CodeUnits (charAt, singleton)
import Kibitzer.Board (Position(..))
import Kibitzer.Cards (Card(..), roomName, suspectName, weaponName)
import Kibitzer.Event (Event(..), EventId, eventIdToInt)
import Kibitzer.Knowledge (Claim(..), Fact, Rule(..))
import Kibitzer.Player (PlayerId(..), playerCountToInt)
import Kibitzer.Suggestion (Suggestion)

-- | Seats are lettered A–F; the letters belong to the table, not the
-- | suspects, since any suspect card can be in any hand.
playerName :: PlayerId -> String
playerName (PlayerId i) = fromMaybe ("P" <> show i) (map singleton (charAt i "ABCDEF"))

cardPhrase :: Card -> String
cardPhrase = case _ of
  SuspectCard s -> suspectName s
  WeaponCard w -> "the " <> weaponName w
  RoomCard r -> "the " <> roomName r

describeSuggestion :: Suggestion -> String
describeSuggestion { suspect, weapon, room } =
  suspectName suspect <> " with the " <> weaponName weapon <> " in the " <> roomName room

-- | Ground-truth prose: includes what the cameras saw, not just what the
-- | watcher was allowed to. The watcher-safe view goes through claims and
-- | facts instead.
describeEvent :: Event -> String
describeEvent = case _ of
  GameDealt { players } ->
    "Cards dealt to "
      <> show (playerCountToInt players)
      <> " players; three sealed in the envelope."
  Moved { player, roll, position } -> case position of
    InRoom room ->
      playerName player <> " rolls " <> show roll <> " and arrives in the " <> roomName room <> "."
    EnRoute { to, remaining } ->
      playerName player
        <> " rolls "
        <> show roll
        <> " and is en route to the "
        <> roomName to
        <> " — "
        <> show remaining
        <> " steps short."
  SuggestionMade { by, suggestion } ->
    playerName by <> " suggests " <> describeSuggestion suggestion <> "."
  Passed { player } ->
    playerName player <> " passes — holding none of the three."
  CardShown { by, to, card } ->
    playerName by <> " shows " <> playerName to <> " a card. (It is " <> cardPhrase card <> ".)"
  AccusationMade { by, accusation, correct } ->
    playerName by
      <> " accuses: "
      <> describeSuggestion accusation
      <> ( if correct then " — correct. " <> playerName by <> " wins."
           else " — wrong. " <> playerName by <> " is out."
         )

describeClaim :: Claim -> String
describeClaim = case _ of
  Holds p c -> playerName p <> " holds " <> cardPhrase c
  Lacks p c -> playerName p <> " does not hold " <> cardPhrase c
  InEnvelope c -> cardPhrase c <> " is in the envelope"
  NotInEnvelope c -> cardPhrase c <> " is not in the envelope"

ruleName :: Rule -> String
ruleName = case _ of
  OwnHand -> "own hand"
  SawCard -> "saw the card"
  PassImpliesLacks -> "passed"
  SingletonDisjunction -> "only candidate left"
  UniqueOwner -> "held elsewhere"
  HandComplete -> "hand is full"
  LastCandidateHand -> "last possible hand"
  EnvelopeByElimination -> "held by no one"
  CategoryCount -> "one per category"
  EnvelopeExcludesHands -> "in the envelope"

eventRef :: EventId -> String
eventRef eid = "E" <> show (eventIdToInt eid)

describeFact :: Fact -> String
describeFact { claim, justification } =
  "["
    <> eventRef justification.source
    <> " · "
    <> ruleName justification.rule
    <> "] "
    <> describeClaim claim
    <> case justification.origin of
      Just origin -> " (resolving the card shown at " <> eventRef origin <> ")"
      Nothing -> ""
