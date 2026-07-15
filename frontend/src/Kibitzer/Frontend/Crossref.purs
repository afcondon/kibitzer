-- | The joins behind the cross-referenced cascade: a hover anywhere —
-- | an orbit token, a possibility bubble, a terminal line — names one
-- | thing, and this module answers what else is implicated. The keys
-- | are already in the data: a fact knows its source event and its
-- | claim names a (location, card) possibility; premises give ancestry.
-- |
-- | The rule is uniform: seed facts from the hover, close over premise
-- | ancestry (hovering a deep inference lights the whole argument that
-- | fed it, back to the observations), then read events and
-- | possibilities off the closed set.
module Kibitzer.Frontend.Crossref
  ( Hover(..)
  , Implicated
  , implicated
  , possOf
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Kibitzer.Event (eventIdToInt)
import Kibitzer.Frontend.Packs.Model as Packs
import Kibitzer.Knowledge (Claim(..), Fact, FactId(..))
import Kibitzer.Player (PlayerCount, PlayerId(..))

data Hover
  = HoverFact Int -- an orbit/grid mark, by raw fact id
  | HoverPoss Int Int -- a pack bubble: location index, card index
  | HoverEvent Int -- a terminal line, by event index

derive instance Eq Hover

type Implicated =
  { facts :: Set Int -- raw fact ids
  , events :: Set Int -- event indexes
  , poss :: Set Int -- pack node ids (Packs.nodeId)
  }

-- | The (location, card) possibility a claim speaks about.
possOf :: PlayerCount -> Claim -> { loc :: Int, card :: Int }
possOf count = case _ of
  Holds (PlayerId p) c -> { loc: p, card: Packs.cardIndex c }
  Lacks (PlayerId p) c -> { loc: p, card: Packs.cardIndex c }
  InEnvelope c -> { loc: Packs.envelopeLoc count, card: Packs.cardIndex c }
  NotInEnvelope c -> { loc: Packs.envelopeLoc count, card: Packs.cardIndex c }

implicated :: PlayerCount -> Array Fact -> Hover -> Implicated
implicated count visible hover =
  { facts: Set.fromFoldable (map fidOf closure)
  , events: Set.fromFoldable (map (\f -> eventIdToInt f.justification.source) closure)
      <> extraEvents
  , poss: Set.fromFoldable (map (\f -> nodeOf f.claim) closure) <> extraPoss
  }
  where
  fidOf f = case f.id of FactId n -> n

  nodeOf claim = let p = possOf count claim in Packs.nodeId p.loc p.card

  seeds = case hover of
    HoverFact n -> Array.fromFoldable (Array.index visible n)
    HoverEvent e -> Array.filter
      (\f -> eventIdToInt f.justification.source == e)
      visible
    HoverPoss loc card -> Array.filter
      (\f -> possOf count f.claim == { loc, card })
      visible

  -- the hovered thing itself stays implicated even when no facts speak
  -- about it (an untouched bubble, an uninformative event)
  extraEvents = case hover of
    HoverEvent e -> Set.singleton e
    _ -> Set.empty

  extraPoss = case hover of
    HoverPoss loc card -> Set.singleton (Packs.nodeId loc card)
    _ -> Set.empty

  -- premise ancestry: facts are id-dense in `visible` and premises
  -- always precede conclusions, so a simple worklist BFS terminates
  closure :: Array Fact
  closure = go seeds (Set.fromFoldable (map fidOf seeds)) []
    where
    go frontier seen acc = case Array.uncons frontier of
      Nothing -> acc
      Just { head: f, tail } ->
        let
          parents = f.justification.premises # Array.mapMaybe
            \(FactId n) ->
              if Set.member n seen then Nothing else Array.index visible n
          seen' = Array.foldl (flip (Set.insert <<< fidOf)) seen parents
        in
          go (tail <> parents) seen' (Array.snoc acc f)
