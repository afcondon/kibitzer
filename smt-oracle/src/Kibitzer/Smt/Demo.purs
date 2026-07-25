-- | The three demo beats, on the golden seed-42 game:
-- |
-- |   1. The gap over time — after each informative event, how many
-- |      claims the observations entail that the watcher hasn't
-- |      derived. The watcher-vs-Z3 story from the Python bettor,
-- |      running natively.
-- |   2. The countermodel as artifact — a claim the watcher can't
-- |      conclude, refuted by a full alternate deal you can look at.
-- |   3. Two grounding stories side by side — for one derived claim,
-- |      the events its proof rests on (⊢) next to the observations
-- |      that force it (⊨, an unsat core).
module Kibitzer.Smt.Demo (main) where

import Prelude

import Baskerville.Explain (explain)
import Baskerville.Kernel (KB, Why(..), isKnown, knownClaims)
import Baskerville.Conformance.Smt (Session, countermodel, entailed, newSession, whyEntailed)
import Data.Array as Array
import Data.Foldable (foldM)
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.String (joinWith)
import Data.String as String
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Kibitzer.Cards (displayName)
import Kibitzer.Event (EventId, eventIdToInt)
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (Claim(..), Knowledge(..), Residue, Rule)
import Kibitzer.Observe (Observation(..), Perspective(..), observeLog)
import Kibitzer.Player (PlayerCount, PlayerId(..))
import Kibitzer.Smt.Fixture (GameTruth, actualDeal, seed42, truthOf)
import Kibitzer.Smt.Theory (cluedoTheory, dealFromModel, renderDeal, seatAtom)
import Kibitzer.Suggestion (suggestionCards)
import Mycroft.SmtLib (Model)
import Mycroft.Solver (newSolver, stop, z3Config)

type WatcherKB = KB Residue Claim Rule EventId

main :: Effect Unit
main = launchAff_ do
  let result = seed42
  let count = result.playerCount
  let obs = observeLog Watcher result.log
  let tl = knowledgeTimeline count Watcher result.log
  let truth = truthOf result
  liftEffect (log "=== kibitzer × mycroft — the watcher and the oracle (seed 42) ===")

  beat1 count obs tl

  case Array.last tl of
    Nothing -> pure unit
    Just (Knowledge kb) -> do
      solver <- newSolver z3Config
      session <- newSession solver (cluedoTheory count obs)
      beat2 session count kb truth
      beat3 session kb
      stop solver

-- Entailment is monotone in the observations, so claims once entailed
-- are cached across prefixes and never re-queried.
beat1 :: PlayerCount -> Array (Tuple EventId Observation) -> Array Knowledge -> Aff Unit
beat1 count obs tl = do
  liftEffect (log "\n— beat 1: the gap over time —")
  liftEffect (log "  entailed-but-underived, after each informative event\n")
  liftEffect (log "  event             derived entailed  gap")
  void (foldM step Set.empty positions)
  where
  positions = obs
    # Array.mapWithIndex (\i ob -> { n: i + 1, ob })
    # Array.filter (\r -> informative r.ob)

  informative (Tuple _ o) = case o of
    ObsDealt _ -> true
    ObsPassed _ -> true
    ObsShowed _ -> true
    _ -> false

  labelOf (Tuple eid o) =
    let
      e = "e" <> padLeft 2 (show (eventIdToInt eid))
    in
      case o of
        ObsDealt _ -> e <> " deal"
        ObsPassed { player } -> e <> " " <> seatAtom player <> " passes"
        ObsShowed { by } -> e <> " " <> seatAtom by <> " shows"
        _ -> e

  step :: Set Claim -> { n :: Int, ob :: Tuple EventId Observation } -> Aff (Set Claim)
  step cache row = case Array.index tl row.n of
    Nothing -> pure cache
    Just (Knowledge kb) -> do
      let theory = cluedoTheory count (Array.take row.n obs)
      solver <- newSolver z3Config
      session <- newSession solver theory
      let unknown = Array.filter (\c -> not (isKnown c kb)) theory.universe
      entailedUnknown <- Array.filterA
        (\c -> if Set.member c cache then pure true else entailed session c)
        unknown
      stop solver
      let derived = Set.size (knownClaims kb)
      let gapN = Array.length entailedUnknown
      liftEffect
        ( log
            ( "  " <> padRight 17 (labelOf row.ob)
                <> padLeft 7 (show derived)
                <> padLeft 9 (show (derived + gapN))
                <> padLeft 5 (show gapN)
                <> "  "
                <> bar gapN
            )
        )
      pure (Set.union cache (Set.fromFoldable entailedUnknown))

beat2 :: Session Claim -> PlayerCount -> WatcherKB -> GameTruth -> Aff Unit
beat2 session count kb truth = do
  liftEffect (log "\n— beat 2: the countermodel as artifact —")
  let candidates = Set.toUnfoldable (suggestionCards truth.solution) <#> InEnvelope
  pick <- firstOpen candidates
  case pick of
    Nothing -> liftEffect (log "  (no open solution claim — the watcher solved everything)")
    Just (Tuple claim model) -> liftEffect do
      log ("  the truth the watcher cannot yet conclude: " <> describeClaim claim)
      log "  and z3 agrees it shouldn't — a full alternate deal where it fails:\n"
      log (renderDeal count (dealFromModel model))
      log "\n  whereas the actual hidden deal was:\n"
      log (renderDeal count (actualDeal truth))
  where
  firstOpen :: Array Claim -> Aff (Maybe (Tuple Claim Model))
  firstOpen cs = case Array.uncons cs of
    Nothing -> pure Nothing
    Just { head, tail }
      | isKnown head kb -> firstOpen tail
      | otherwise -> countermodel session head >>= case _ of
          Just m -> pure (Just (Tuple head m))
          Nothing -> firstOpen tail

beat3 :: Session Claim -> WatcherKB -> Aff Unit
beat3 session kb = do
  liftEffect (log "\n— beat 3: two grounding stories, side by side —")
  let
    holdsClaims = Set.toUnfoldable (knownClaims kb) # Array.filter case _ of
      Holds _ _ -> true
      _ -> false
  case Array.head holdsClaims of
    Nothing -> liftEffect (log "  (no held-card conclusions this game)")
    Just claim -> do
      liftEffect (log ("  the claim: " <> describeClaim claim <> "\n"))
      case explain claim kb of
        Nothing -> pure unit
        Just dag -> do
          let
            events = dag.nodes >>= \f -> case f.why of
              ByRule d -> (if Array.null d.premises then [ d.source ] else []) <> d.anchors
              Axiom s -> [ s ]
            labels = Array.sort (Array.nub (map eventIdToInt events)) <#> \i -> "e" <> show i
          liftEffect (log ("  ⊢ the proof rests on events:       " <> joinWith ", " labels))
      core <- whyEntailed session claim
      case core of
        Nothing -> liftEffect (log "  ⊨ not entailed — which would be a soundness bug")
        Just names -> liftEffect
          (log ("  ⊨ the unsat core of observations:  " <> joinWith ", " (Array.sort names)))
      liftEffect (log "\n  the proof is one road there; the core is which observations force")
      liftEffect (log "  the destination. when they differ, the difference is the story.")

describeClaim :: Claim -> String
describeClaim = case _ of
  Holds (PlayerId i) c -> "player " <> show i <> " holds " <> displayName c
  Lacks (PlayerId i) c -> "player " <> show i <> " lacks " <> displayName c
  InEnvelope c -> displayName c <> " is in the envelope"
  NotInEnvelope c -> displayName c <> " is not in the envelope"

bar :: Int -> String
bar n = joinWith "" (Array.replicate (min n 40) "█")

padLeft :: Int -> String -> String
padLeft n s = joinWith "" (Array.replicate (max 0 (n - String.length s)) " ") <> s

padRight :: Int -> String -> String
padRight n s = s <> joinWith "" (Array.replicate (max 0 (n - String.length s)) " ")
