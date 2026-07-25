-- | Cluedo as an `SmtTheory`: 21 `holder-<card>` constants over an
-- | enumerated `Place` sort (one seat per player, plus the envelope),
-- | hand sizes and the one-per-category envelope rule as cardinality
-- | constraints, and the watcher's observation stream as *named*
-- | assertions — names are what unsat cores are made of, so every ⊨
-- | verdict can point back at the events that force it.
-- |
-- | The theory is built from the observation stream, never from the
-- | engine's conclusions: the oracle must be independent of the thing
-- | it judges. Note the shown-card disjunctions the ⊢ side keeps as
-- | residue are first-class assertions here.
module Kibitzer.Smt.Theory
  ( cluedoTheory
  , cardAtom
  , seatAtom
  , envelopeAtom
  , Holder(..)
  , dealFromModel
  , renderDeal
  ) where

import Prelude

import Baskerville.Oracle.Smt (SmtTheory)
import Data.Array as Array
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Data.String (joinWith)
import Data.String as String
import Data.Tuple (Tuple(..))
import Kibitzer.Cards (Card(..), Category, Room(..), Suspect(..), Weapon(..), allCards, allCategories, cardsIn, displayName)
import Kibitzer.Event (EventId, eventIdToInt)
import Kibitzer.Knowledge (Claim(..))
import Kibitzer.Observe (Observation(..))
import Kibitzer.Player (PlayerCount, PlayerId(..), allPlayers)
import Kibitzer.Suggestion (suggestionCards)
import Mycroft.SExpr (SExpr(..))
import Mycroft.SmtLib (Model, Term(..), countEq, eqT, intLit, lookupAtom, notT, orT, var)

cardAtom :: Card -> String
cardAtom = case _ of
  SuspectCard s -> case s of
    Scarlett -> "scarlett"
    Mustard -> "mustard"
    White -> "white"
    Green -> "green"
    Peacock -> "peacock"
    Plum -> "plum"
  WeaponCard w -> case w of
    Candlestick -> "candlestick"
    Knife -> "knife"
    LeadPipe -> "lead-pipe"
    Revolver -> "revolver"
    Rope -> "rope"
    Wrench -> "wrench"
  RoomCard r -> case r of
    Kitchen -> "kitchen"
    Ballroom -> "ballroom"
    Conservatory -> "conservatory"
    DiningRoom -> "dining-room"
    BilliardRoom -> "billiard-room"
    Library -> "library"
    Lounge -> "lounge"
    Hall -> "hall"
    Study -> "study"

seatAtom :: PlayerId -> String
seatAtom (PlayerId i) = "seat" <> show i

envelopeAtom :: String
envelopeAtom = "envelope"

holderVar :: Card -> Term
holderVar c = var ("holder-" <> cardAtom c)

seatTerm :: PlayerId -> Term
seatTerm = var <<< seatAtom

encode :: Claim -> Term
encode = case _ of
  Holds p c -> eqT (holderVar c) (seatTerm p)
  Lacks p c -> notT (eqT (holderVar c) (seatTerm p))
  InEnvelope c -> eqT (holderVar c) (var envelopeAtom)
  NotInEnvelope c -> notT (eqT (holderVar c) (var envelopeAtom))

assertCmd :: Term -> SExpr
assertCmd (Term t) = List [ Atom "assert", t ]

enumDecl :: String -> Array String -> SExpr
enumDecl name ctors =
  List
    [ Atom "declare-datatypes"
    , List [ List [ Atom name, Atom "0" ] ]
    , List [ List (map (\c -> List [ Atom c ]) ctors) ]
    ]

holderDecl :: Card -> SExpr
holderDecl c = List [ Atom "declare-const", Atom ("holder-" <> cardAtom c), Atom "Place" ]

-- | Game rule, not observation: the envelope holds exactly one card of
-- | each category. (Hand sizes are observations — they arrive with the
-- | deal event, so they assert under its name.)
categoryAxiom :: Category -> SExpr
categoryAxiom category = assertCmd
  ( eqT
      (countEq (map holderVar (Set.toUnfoldable (cardsIn category))) (var envelopeAtom))
      (intLit 1)
  )

observationAssertions :: Array (Tuple EventId Observation) -> Array { name :: String, term :: Term }
observationAssertions obs = obs >>= \(Tuple eid o) ->
  let
    e = "e" <> show (eventIdToInt eid)
  in
    case o of
      ObsDealt { handSizes, ownHand } ->
        ( (Map.toUnfoldable handSizes :: Array (Tuple PlayerId Int)) <#> \(Tuple p size) ->
            { name: e <> "-hand-" <> seatAtom p
            , term: eqT (countEq (map holderVar allCards) (seatTerm p)) (intLit size)
            }
        ) <> case ownHand of
          Nothing -> []
          Just { player, hand } -> Set.toUnfoldable hand <#> \c ->
            { name: e <> "-own-" <> cardAtom c
            , term: eqT (holderVar c) (seatTerm player)
            }
      ObsPassed { player, suggestion } ->
        Set.toUnfoldable (suggestionCards suggestion) <#> \c ->
          { name: e <> "-pass-" <> seatAtom player <> "-" <> cardAtom c
          , term: notT (eqT (holderVar c) (seatTerm player))
          }
      ObsShowed { by, card, suggestion } -> case card of
        Just c ->
          [ { name: e <> "-saw-" <> seatAtom by <> "-" <> cardAtom c
            , term: eqT (holderVar c) (seatTerm by)
            }
          ]
        Nothing ->
          [ { name: e <> "-shown-" <> seatAtom by
            , term: orT
                ( Set.toUnfoldable (suggestionCards suggestion) <#> \c ->
                    eqT (holderVar c) (seatTerm by)
                )
            }
          ]
      ObsMoved _ -> []
      ObsSuggestion _ -> []
      ObsAccused _ -> []

-- | The theory for a perspective's observation prefix. The claim
-- | universe — every Holds/Lacks/InEnvelope/NotInEnvelope — is 210
-- | claims at four players; the world space it stands in for is the
-- | ~10¹¹ deals, which is why the counting oracle never came to Cluedo.
cluedoTheory :: PlayerCount -> Array (Tuple EventId Observation) -> SmtTheory Claim
cluedoTheory count obs =
  { declare:
      [ enumDecl "Place" (map seatAtom (allPlayers count) <> [ envelopeAtom ]) ]
        <> map holderDecl allCards
        <> map categoryAxiom allCategories
  , encode
  , observations: observationAssertions obs
  , universe:
      (allPlayers count >>= \p -> allCards >>= \c -> [ Holds p c, Lacks p c ])
        <> (allCards >>= \c -> [ InEnvelope c, NotInEnvelope c ])
  }

data Holder = Seat PlayerId | Envelope

derive instance Eq Holder
derive instance Ord Holder

instance Show Holder where
  show = case _ of
    Seat (PlayerId i) -> "(Seat " <> show i <> ")"
    Envelope -> "Envelope"

decodeHolder :: String -> Maybe Holder
decodeHolder s
  | s == envelopeAtom = Just Envelope
  | otherwise = String.stripPrefix (String.Pattern "seat") s
      >>= Int.fromString
      <#> (Seat <<< PlayerId)

-- | Read a full deal out of a solver model — the countermodel made
-- | into an artifact you can look at.
dealFromModel :: Model -> Map Card Holder
dealFromModel model = Map.fromFoldable do
  c <- allCards
  case lookupAtom model ("holder-" <> cardAtom c) >>= decodeHolder of
    Just h -> [ Tuple c h ]
    Nothing -> []

renderDeal :: PlayerCount -> Map Card Holder -> String
renderDeal count deal =
  joinWith "\n" (map line (map Seat (allPlayers count) <> [ Envelope ]))
  where
  line holder =
    let
      cards = Map.toUnfoldable deal
        # Array.filter (\(Tuple _ h) -> h == holder)
        # map (\(Tuple c _) -> displayName c)
      label = case holder of
        Seat (PlayerId i) -> "Player " <> show i
        Envelope -> "Envelope"
    in
      "  " <> pad 10 label <> " " <> joinWith ", " cards

  pad n s = s <> joinWith "" (Array.replicate (max 0 (n - String.length s)) " ")
