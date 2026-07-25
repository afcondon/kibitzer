-- | The native bettor validation: on every tested seed, each fact the
-- | watcher derives must be z3-entailed by the observations alone
-- | (`unsound` empty — ⊢ never outruns ⊨), and every claim in the gap
-- | must be true of the actual hidden deal (⊨ never lies either). The
-- | seed-42 game gets the deep pass: cores, countermodels, and all
-- | three `explainOr` outcomes.
module Test.Smt.Main (main) where

import Prelude

import Baskerville.Kernel (knownClaims)
import Baskerville.Conformance.Smt (consistent, explainOr, gap, newSession, unsound, whyEntailed)
import Baskerville.Conformance (Refutation(..))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Kibitzer.Cards (Card(..))
import Kibitzer.Infer (knowledgeTimeline)
import Kibitzer.Knowledge (Claim(..), Knowledge(..))
import Kibitzer.Observe (Perspective(..), observeLog)
import Kibitzer.Player (PlayerId(..))
import Kibitzer.Smt.Fixture (gameFor, trueOfDeal, truthOf)
import Kibitzer.Smt.Theory (Holder(..), cluedoTheory, dealFromModel)
import Mycroft.Solver (newSolver, stop, z3Config)
import Test.Assert (assertEqual, assertTrue')

main :: Effect Unit
main = launchAff_ do
  seedCheck true 42
  for_ [ 7, 11, 33 ] (seedCheck false)
  liftEffect (log "All kibitzer-smt tests passed")

seedCheck :: Boolean -> Int -> Aff Unit
seedCheck deep seedInt = do
  liftEffect (log ("Smt: seed " <> show seedInt <> " — the watcher against the oracle"))
  let result = gameFor seedInt
  let count = result.playerCount
  let obs = observeLog Watcher result.log
  let truth = truthOf result
  case Array.last (knowledgeTimeline count Watcher result.log) of
    Nothing -> liftEffect (assertTrue' "timeline is nonempty" false)
    Just (Knowledge kb) -> do
      solver <- newSolver z3Config
      session <- newSession solver (cluedoTheory count obs)

      liftEffect (assertTrue' "observations are consistent" (consistent session))

      -- ⊢ never outruns ⊨: every derived fact is entailed.
      bad <- unsound session kb
      liftEffect (assertEqual { actual: bad, expected: [] })

      -- ⊨ never lies: everything entailed-but-underived is true of the
      -- hidden deal (which only the test can see).
      g <- gap session kb
      liftEffect
        ( assertTrue' "gap claims are true of the hidden deal"
            (Array.all (trueOfDeal truth) g)
        )

      when deep do
        liftEffect (log "Smt: seed 42 deep pass — cores and countermodels")

        -- a derived claim explains via ⊢ and carries a ⊨ core
        case Array.head (Set.toUnfoldable (knownClaims kb)) of
          Nothing -> liftEffect (assertTrue' "watcher derived something" false)
          Just claim -> do
            r <- explainOr session kb claim
            liftEffect (assertTrue' "derived claim gets its dag" (isRight r))
            core <- whyEntailed session claim
            case core of
              Nothing -> liftEffect (assertTrue' "derived claim is entailed" false)
              Just names -> do
                liftEffect (assertTrue' "core is nonempty" (not (Array.null names)))
                let obsNames = (cluedoTheory count obs).observations <#> _.name
                liftEffect
                  ( assertTrue' "core only cites observations"
                      (Array.all (\n -> Array.elem n obsNames) names)
                  )

        -- a false claim (the solution suspect in someone's hand) draws a
        -- full countermodel: 21 cards, and that card not at that seat
        let falseClaim = Holds (PlayerId 0) (SuspectCard truth.solution.suspect)
        r <- explainOr session kb falseClaim
        case r of
          Left (Countermodel m) -> do
            let deal = dealFromModel m
            liftEffect (assertEqual { actual: Map.size deal, expected: 21 })
            liftEffect
              ( assertTrue' "countermodel refutes the claim"
                  ( Map.lookup (SuspectCard truth.solution.suspect) deal
                      /= Just (Seat (PlayerId 0))
                  )
              )
          _ -> liftEffect (assertTrue' "false claim draws a countermodel" false)

        -- the gap, pointed at one claim: Underived, not a countermodel
        case Array.head g of
          Nothing -> liftEffect (log "Smt: (no gap at this seed — skipping Underived beat)")
          Just gapClaim -> do
            rg <- explainOr session kb gapClaim
            case rg of
              Left Underived -> pure unit
              _ -> liftEffect (assertTrue' "gap claim is Underived" false)

      stop solver
      liftEffect
        ( log
            ( "Smt: seed " <> show seedInt <> " ok — "
                <> show (Set.size (knownClaims kb))
                <> " facts derived, gap "
                <> show (Array.length g)
            )
        )

isRight :: forall a b. Either a b -> Boolean
isRight = case _ of
  Right _ -> true
  Left _ -> false
