-- | The inference engine: fold `learn` over an observation stream and you
-- | have a mind. The watcher folds over the public stream; a player folds
-- | over the same stream plus their private sightings. Same engine, same
-- | rules — the only difference is what was witnessed.
-- |
-- | Since the jtms-port the fixpoint machinery lives in `Jtms.Engine`; this
-- | module supplies the domain: the deduction rules (in prim form — they
-- | predate the library's eDSL and stay verbatim so the golden feeds do
-- | too) and the residue refinement (`pruneDisjunctions`). Termination is
-- | by monotonicity, exactly as before: rules only add claims to finite
-- | sets, refinement only shrinks candidate sets, nothing retracts.
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
import Jtms.Engine as Engine
import Kibitzer.Cards (Card, allCards, allCategories, cardsIn)
import Kibitzer.Event (EventId, Log)
import Kibitzer.Knowledge (Claim(..), Disjunction(..), Knowledge(..), Residue, Rule(..), addDisjunction, addFact, disjunctions, envelopeIn, envelopeOut, factIdFor, handSizesOf, heldByAnyone, heldEntries, holdsOf, lacksOf, playerCountOf, toWhy, withHandSizes, emptyKnowledge)
import Jtms.Kernel (FactId)
import Kibitzer.Observe (Observation(..), Perspective, observeLog)
import Kibitzer.Player (PlayerCount, PlayerId, allPlayers)
import Kibitzer.Suggestion (suggestionCards)

-- | What a single deduction rule may emit: a claim, under its rule's name,
-- | citing the show-events it drew on and the prior facts it consumed.
type Derived =
  { claim :: Claim
  , rule :: Rule
  , origins :: Array EventId
  , premises :: Array FactId
  }

learn :: Tuple EventId Observation -> Knowledge -> Knowledge
learn (Tuple source observation) knowledge =
  saturate source (direct observation)
  where
  -- Direct consequences of witnessing: no premises, no origins.
  conclude rule claims k =
    foldl
      ( \acc claim ->
          addFact { claim, justification: { rule, source, origins: [], premises: [] } } acc
      )
      k
      claims

  direct = case _ of
    ObsDealt { handSizes, ownHand } ->
      let
        sized = withHandSizes handSizes knowledge
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
            , initial: suggestionCards suggestion
            , source
            , resolved: false
            }
        )
        knowledge
    -- Deliberately learns nothing: a correct accusation reveals the
    -- envelope, and the demo's whole point is what the watcher knew
    -- *before* the reveal.
    ObsAccused _ -> knowledge

-- | Kibitzer's rules and residue refinement, packaged for `Jtms.Engine`.
engine :: Engine.Engine Residue Claim Rule EventId
engine =
  { rules: allRules <#> \rule kb ->
      rule (Knowledge kb) <#> \d ->
        { claim: d.claim, rule: d.rule, premises: d.premises, anchors: d.origins }
  , refine: \kb r ->
      r { disjunctions = map (pruneOne (Knowledge kb)) r.disjunctions }
  }

saturate :: EventId -> Knowledge -> Knowledge
saturate source (Knowledge kb) = Knowledge (Engine.saturate engine source kb)

-- | Fixed application order — part of the observable spec (see module doc).
allRules :: Array (Knowledge -> Array Derived)
allRules =
  [ ruleSingletonDisjunction
  , ruleUniqueOwner
  , ruleHandComplete
  , ruleLastCandidateHand
  , ruleDisjunctionCapacity
  , ruleDisjunctionPigeonhole
  , ruleEnvelopeByElimination
  , ruleCategoryCount
  , ruleEnvelopeExcludesHands
  ]

-- | Shrink an unresolved disjunction: a candidate the shower is known
-- | to lack, or known to be held by *someone else*, cannot be the card
-- | that was shown. Mark the disjunction resolved once the shower is known
-- | to hold one of its candidates.
pruneOne :: Knowledge -> Disjunction -> Disjunction
pruneOne knowledge whole@(Disjunction d)
  | d.resolved = whole
  | otherwise =
      let
        othersHold = heldEntries knowledge
          # Array.filter (\(p /\ _) -> p /= d.player)
          # map (\(_ /\ cards) -> cards)
          # Set.unions
        impossible c = Set.member c (lacksOf knowledge d.player) || Set.member c othersHold
        candidates = Set.filter (not <<< impossible) d.candidates
        resolved = not (Set.isEmpty (Set.intersection candidates (holdsOf knowledge d.player)))
      in
        Disjunction (d { candidates = candidates, resolved = resolved })

ruleSingletonDisjunction :: Knowledge -> Array Derived
ruleSingletonDisjunction knowledge =
  disjunctions knowledge # Array.mapMaybe case _ of
    Disjunction d
      | not d.resolved, Set.size d.candidates == 1, Just c <- Set.findMin d.candidates ->
          Just
            { claim: Holds d.player c
            , rule: SingletonDisjunction
            , origins: [ d.source ]
            , premises:
                Array.mapMaybe (pruneEvidence knowledge d.player)
                  (Set.toUnfoldable (Set.difference d.initial d.candidates))
            }
    _ -> Nothing

-- | The fact that ruled a candidate out of a disjunction: the shower is
-- | known to lack it, or someone else is known to hold it.
pruneEvidence :: Knowledge -> PlayerId -> Card -> Maybe FactId
pruneEvidence knowledge player c =
  case factIdFor (Lacks player c) knowledge of
    Just fid -> Just fid
    Nothing ->
      Array.findMap (\q -> factIdFor (Holds q c) knowledge)
        (Array.filter (_ /= player) (allPlayers (playerCountOf knowledge)))

ruleUniqueOwner :: Knowledge -> Array Derived
ruleUniqueOwner knowledge = do
  p /\ held <- heldEntries knowledge
  c <- Set.toUnfoldable held
  let premises = Array.fromFoldable (factIdFor (Holds p c) knowledge)
  let excludeOthers q = { claim: Lacks q c, rule: UniqueOwner, origins: [], premises }
  Array.cons
    { claim: NotInEnvelope c, rule: UniqueOwner, origins: [], premises }
    (map excludeOthers (Array.filter (_ /= p) (allPlayers (playerCountOf knowledge))))

ruleHandComplete :: Knowledge -> Array Derived
ruleHandComplete knowledge = do
  p /\ size <- Map.toUnfoldable (handSizesOf knowledge) :: Array (PlayerId /\ Int)
  let held = holdsOf knowledge p
  guard (Set.size held == size)
  let premises = holdsPremises knowledge p held
  c <- Array.filter (\c -> not (Set.member c held)) allCards
  pure { claim: Lacks p c, rule: HandComplete, origins: [], premises }

-- | Every `Holds p c` fact behind a set of held cards.
holdsPremises :: Knowledge -> PlayerId -> Set Card -> Array FactId
holdsPremises knowledge p held =
  Array.mapMaybe (\c -> factIdFor (Holds p c) knowledge) (Set.toUnfoldable held)

ruleLastCandidateHand :: Knowledge -> Array Derived
ruleLastCandidateHand knowledge = do
  c <- Set.toUnfoldable (envelopeOut knowledge)
  guard (not (Set.member c (heldByAnyone knowledge)))
  case Array.filter (\p -> not (Set.member c (lacksOf knowledge p))) (allPlayers (playerCountOf knowledge)) of
    [ p ] ->
      let
        excluded = Array.filter (_ /= p) (allPlayers (playerCountOf knowledge))
        premises =
          Array.fromFoldable (factIdFor (NotInEnvelope c) knowledge)
            <> Array.mapMaybe (\q -> factIdFor (Lacks q c) knowledge) excluded
      in
        pure { claim: Holds p c, rule: LastCandidateHand, origins: [], premises }
    _ -> []

-- | A player with f free hand slots and f pairwise-disjoint unresolved
-- | disjunctions has every unknown card spoken for: each unresolved
-- | disjunction (no known candidate — pruning guarantees it) must be
-- | satisfied by a distinct unknown card, so the hand lies inside the
-- | family's candidate union.
-- |
-- | Crucially, EVERY size-f disjoint family yields that entailment
-- | simultaneously, so the hand lies inside the *intersection* of their
-- | unions — and it must be the intersection, not one greedily chosen
-- | family: a better-informed mind prunes the pools differently, and a
-- | single-family conclusion can vary with the choice, breaking the
-- | player-⊇-watcher theorem. Intersecting over all families restores it
-- | (any watcher family survives, pruned but disjoint, into every
-- | better-informed view).
ruleDisjunctionCapacity :: Knowledge -> Array Derived
ruleDisjunctionCapacity knowledge = do
  p /\ size <- Map.toUnfoldable (handSizesOf knowledge) :: Array (PlayerId /\ Int)
  let held = holdsOf knowledge p
  let free = size - Set.size held
  guard (free > 0)
  let
    unresolved = Array.mapMaybe
      ( case _ of
          Disjunction d | not d.resolved, d.player == p ->
            Just { candidates: d.candidates, source: d.source }
          _ -> Nothing
      )
      (disjunctions knowledge)
    pools = Array.nub (map _.candidates unresolved)
  case reachableUnion free pools of
    Nothing -> []
    Just reachable -> do
      -- Provenance is deliberately partial here: the argument spans every
      -- qualifying family, so we cite the held cards and all the involved
      -- show-events — an anchor for the arcs, not a proof term.
      let premises = holdsPremises knowledge p held
      let origins = Array.nub (map _.source unresolved)
      c <- Array.filter
        (\c -> not (Set.member c held) && not (Set.member c reachable))
        allCards
      pure { claim: Lacks p c, rule: DisjunctionCapacity, origins, premises }

-- | The intersection of the candidate unions over every pairwise-disjoint
-- | family of exactly `size` pools; Nothing when no such family exists.
reachableUnion :: Int -> Array (Set Card) -> Maybe (Set Card)
reachableUnion size pools = case familyUnions size pools of
  [] -> Nothing
  unions -> Just (foldl Set.intersection (Set.unions unions) unions)

-- | Candidate unions of all size-k pairwise-disjoint subfamilies.
familyUnions :: Int -> Array (Set Card) -> Array (Set Card)
familyUnions 0 _ = [ Set.empty ]
familyUnions k pools = case Array.uncons pools of
  Nothing -> []
  Just { head: s, tail } ->
    let
      compatible = Array.filter (\t -> Set.isEmpty (Set.intersection s t)) tail
      taking = map (Set.union s) (familyUnions (k - 1) compatible)
      skipping = familyUnions k tail
    in
      taking <> skipping

-- | Two *different* players each showed a card from the same two-card
-- | candidate pool. A card sits in exactly one hand, so the pool is
-- | exhausted: both cards are in hands, and neither is in the envelope.
-- | (The k=3 generalisation exists; pairs already close most of the gap.)
ruleDisjunctionPigeonhole :: Knowledge -> Array Derived
ruleDisjunctionPigeonhole knowledge = do
  let
    narrow = Array.mapMaybe
      ( case _ of
          Disjunction d | not d.resolved, Set.size d.candidates <= 2 ->
            Just { player: d.player, candidates: d.candidates, source: d.source }
          _ -> Nothing
      )
      (disjunctions knowledge)
  Tuple i first <- Array.mapWithIndex Tuple narrow
  second <- Array.drop (i + 1) narrow
  guard (first.player /= second.player)
  let pool = Set.union first.candidates second.candidates
  guard (Set.size pool == 2)
  c <- Set.toUnfoldable pool
  pure
    { claim: NotInEnvelope c
    , rule: DisjunctionPigeonhole
    , origins: [ first.source, second.source ]
    , premises: []
    }

ruleEnvelopeByElimination :: Knowledge -> Array Derived
ruleEnvelopeByElimination knowledge = do
  c <- allCards
  guard (Array.all (\p -> Set.member c (lacksOf knowledge p)) (allPlayers (playerCountOf knowledge)))
  let
    premises = Array.mapMaybe (\p -> factIdFor (Lacks p c) knowledge)
      (allPlayers (playerCountOf knowledge))
  pure { claim: InEnvelope c, rule: EnvelopeByElimination, origins: [], premises }

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
    let
      premises = Array.mapMaybe (\o -> factIdFor (NotInEnvelope o) knowledge)
        (Set.toUnfoldable out)
    case Set.findMin (Set.difference cards out) of
      Just c -> pure { claim: InEnvelope c, rule: CategoryCount, origins: [], premises }
      Nothing -> []

  siblingsOut = do
    category <- allCategories
    let cards = cardsIn category
    c <- Set.toUnfoldable (Set.intersection cards (envelopeIn knowledge))
    let premises = Array.fromFoldable (factIdFor (InEnvelope c) knowledge)
    sibling <- Set.toUnfoldable (Set.delete c cards)
    pure { claim: NotInEnvelope sibling, rule: CategoryCount, origins: [], premises }

ruleEnvelopeExcludesHands :: Knowledge -> Array Derived
ruleEnvelopeExcludesHands knowledge = do
  c <- Set.toUnfoldable (envelopeIn knowledge)
  let premises = Array.fromFoldable (factIdFor (InEnvelope c) knowledge)
  p <- allPlayers (playerCountOf knowledge)
  pure { claim: Lacks p c, rule: EnvelopeExcludesHands, origins: [], premises }

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
