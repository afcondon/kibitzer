-- | The inference engine: fold `learn` over an observation stream and you
-- | have a mind. The watcher folds over the public stream; a player folds
-- | over the same stream plus their private sightings. Same engine, same
-- | rules — the only difference is what was witnessed.
-- |
-- | `learn` records the direct consequences of one observation, then runs
-- | `saturate`: a fixpoint over the deduction rules below. Termination is
-- | by monotonicity — every rule only adds claims to finite sets or shrinks
-- | disjunction candidate sets, and no claim is ever retracted, so a pass
-- | that changes nothing is the fixpoint and one must come.
-- |
-- | Rule order within a pass is fixed and documented (`allRules`), because
-- | it decides which justification a multiply-derivable fact receives, and
-- | golden tests pin the feed.
module Kibitzer.Infer
  ( learn
  , saturate
  , knowledgeAt
  , knowledgeTimeline
  ) where

import Prelude

import Control.Alternative (guard)
import Data.Array as Array
import Data.Foldable (foldl)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested (type (/\), (/\))
import Kibitzer.Cards (Card, allCards, allCategories, cardsIn)
import Kibitzer.Event (EventId, Log)
import Kibitzer.Knowledge (Claim(..), Disjunction(..), Knowledge(..), Rule(..), addDisjunction, addFact, emptyKnowledge, envelopeIn, envelopeOut, heldByAnyone, holdsOf, lacksOf)
import Kibitzer.Observe (Observation(..), Perspective, observeLog)
import Kibitzer.Player (PlayerCount, PlayerId, allPlayers)
import Kibitzer.Suggestion (suggestionCards)

-- | What a single deduction rule may emit: a claim, under its rule's name,
-- | optionally pointing back at the show-event it finally resolved.
type Derived = { claim :: Claim, rule :: Rule, origin :: Maybe EventId }

learn :: Tuple EventId Observation -> Knowledge -> Knowledge
learn (Tuple source observation) knowledge =
  saturate source (direct observation)
  where
  conclude rule claims k =
    foldl
      (\acc claim -> addFact { claim, justification: { rule, source, origin: Nothing } } acc)
      k
      claims

  direct = case _ of
    ObsDealt { handSizes, ownHand } ->
      let
        sized = case knowledge of Knowledge k -> Knowledge (k { handSizes = handSizes })
      in
        case ownHand of
          Nothing -> sized
          Just { player, hand } ->
            conclude OwnHand (map (Holds player) (Set.toUnfoldable hand)) sized
    -- Deliberately learns nothing: movement is public, but none of the
    -- deduction rules use it — a token's path is a hunch, not a fact,
    -- and the notebook must never hold hunches.
    ObsMoved _ -> knowledge
    ObsSuggestion _ -> knowledge
    ObsPassed { player, suggestion } ->
      conclude PassImpliesLacks
        (map (Lacks player) (Set.toUnfoldable (suggestionCards suggestion)))
        knowledge
    ObsShowed { by, suggestion, card } -> case card of
      Just c -> conclude SawCard [ Holds by c ] knowledge
      Nothing -> addDisjunction
        ( Disjunction
            { player: by
            , candidates: suggestionCards suggestion
            , source
            , resolved: false
            }
        )
        knowledge
    -- Deliberately learns nothing: a correct accusation reveals the
    -- envelope, and the demo's whole point is what the watcher knew
    -- *before* the reveal.
    ObsAccused _ -> knowledge

saturate :: EventId -> Knowledge -> Knowledge
saturate source knowledge =
  let
    next = saturateOnce source knowledge
  in
    if next == knowledge then knowledge else saturate source next

saturateOnce :: EventId -> Knowledge -> Knowledge
saturateOnce source knowledge =
  let
    pruned = pruneDisjunctions knowledge
    derived = Array.concatMap (\rule -> rule pruned) allRules
  in
    foldl
      ( \k { claim, rule, origin } ->
          addFact { claim, justification: { rule, source, origin } } k
      )
      pruned
      derived

-- | Fixed application order — part of the observable spec (see module doc).
allRules :: Array (Knowledge -> Array Derived)
allRules =
  [ ruleSingletonDisjunction
  , ruleUniqueOwner
  , ruleHandComplete
  , ruleLastCandidateHand
  , ruleEnvelopeByElimination
  , ruleCategoryCount
  , ruleEnvelopeExcludesHands
  ]

-- | Shrink every unresolved disjunction: a candidate the shower is known
-- | to lack, or known to be held by *someone else*, cannot be the card
-- | that was shown. Mark the disjunction resolved once the shower is known
-- | to hold one of its candidates.
pruneDisjunctions :: Knowledge -> Knowledge
pruneDisjunctions knowledge@(Knowledge k) =
  Knowledge (k { disjunctions = map prune k.disjunctions })
  where
  prune whole@(Disjunction d)
    | d.resolved = whole
    | otherwise =
        let
          othersHold = Set.unions (Map.values (Map.filterKeys (_ /= d.player) k.holds))
          impossible c = Set.member c (lacksOf knowledge d.player) || Set.member c othersHold
          candidates = Set.filter (not <<< impossible) d.candidates
          resolved = not (Set.isEmpty (Set.intersection candidates (holdsOf knowledge d.player)))
        in
          Disjunction (d { candidates = candidates, resolved = resolved })

ruleSingletonDisjunction :: Knowledge -> Array Derived
ruleSingletonDisjunction (Knowledge k) =
  k.disjunctions # Array.mapMaybe case _ of
    Disjunction d
      | not d.resolved, Set.size d.candidates == 1, Just c <- Set.findMin d.candidates ->
          Just { claim: Holds d.player c, rule: SingletonDisjunction, origin: Just d.source }
    _ -> Nothing

ruleUniqueOwner :: Knowledge -> Array Derived
ruleUniqueOwner knowledge@(Knowledge k) = do
  p /\ held <- heldEntries knowledge
  c <- Set.toUnfoldable held
  let excludeOthers q = { claim: Lacks q c, rule: UniqueOwner, origin: Nothing }
  Array.cons
    { claim: NotInEnvelope c, rule: UniqueOwner, origin: Nothing }
    (map excludeOthers (Array.filter (_ /= p) (allPlayers k.playerCount)))

ruleHandComplete :: Knowledge -> Array Derived
ruleHandComplete knowledge@(Knowledge k) = do
  p /\ size <- Map.toUnfoldable k.handSizes :: Array (PlayerId /\ Int)
  let held = holdsOf knowledge p
  guard (Set.size held == size)
  c <- Array.filter (\c -> not (Set.member c held)) allCards
  pure { claim: Lacks p c, rule: HandComplete, origin: Nothing }

ruleLastCandidateHand :: Knowledge -> Array Derived
ruleLastCandidateHand knowledge@(Knowledge k) = do
  c <- Set.toUnfoldable (envelopeOut knowledge)
  guard (not (Set.member c (heldByAnyone knowledge)))
  case Array.filter (\p -> not (Set.member c (lacksOf knowledge p))) (allPlayers k.playerCount) of
    [ p ] -> pure { claim: Holds p c, rule: LastCandidateHand, origin: Nothing }
    _ -> []

ruleEnvelopeByElimination :: Knowledge -> Array Derived
ruleEnvelopeByElimination knowledge@(Knowledge k) = do
  c <- allCards
  guard (Array.all (\p -> Set.member c (lacksOf knowledge p)) (allPlayers k.playerCount))
  pure { claim: InEnvelope c, rule: EnvelopeByElimination, origin: Nothing }

-- | The envelope holds exactly one card per category, counted both ways:
-- | all-but-one excluded means the last one is in; one known in means the
-- | rest of its category is out.
ruleCategoryCount :: Knowledge -> Array Derived
ruleCategoryCount knowledge = lastOneIn <> siblingsOut
  where
  lastOneIn = do
    category <- allCategories
    let cards = cardsIn category
    let out = Set.intersection cards (envelopeOut knowledge)
    guard (Set.size cards - Set.size out == 1)
    case Set.findMin (Set.difference cards out) of
      Just c -> pure { claim: InEnvelope c, rule: CategoryCount, origin: Nothing }
      Nothing -> []

  siblingsOut = do
    category <- allCategories
    let cards = cardsIn category
    c <- Set.toUnfoldable (Set.intersection cards (envelopeIn knowledge))
    sibling <- Set.toUnfoldable (Set.delete c cards)
    pure { claim: NotInEnvelope sibling, rule: CategoryCount, origin: Nothing }

ruleEnvelopeExcludesHands :: Knowledge -> Array Derived
ruleEnvelopeExcludesHands knowledge@(Knowledge k) = do
  c <- Set.toUnfoldable (envelopeIn knowledge)
  p <- allPlayers k.playerCount
  pure { claim: Lacks p c, rule: EnvelopeExcludesHands, origin: Nothing }

heldEntries :: Knowledge -> Array (PlayerId /\ Set Card)
heldEntries (Knowledge k) = Map.toUnfoldable k.holds

-- | The mind of a perspective after the first n events.
knowledgeAt :: PlayerCount -> Perspective -> Int -> Log -> Knowledge
knowledgeAt count perspective n log =
  foldl (flip learn) (emptyKnowledge count)
    (Array.take n (observeLog perspective log))

-- | Every intermediate mind, position 0 (knowing nothing) through position
-- | `length log`. One scan when a game loads; scrubbing then just indexes.
knowledgeTimeline :: PlayerCount -> Perspective -> Log -> Array Knowledge
knowledgeTimeline count perspective log =
  Array.cons empty (Array.scanl (flip learn) empty (observeLog perspective log))
  where
  empty = emptyKnowledge count
