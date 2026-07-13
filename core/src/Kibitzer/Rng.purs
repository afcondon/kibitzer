-- | A tiny pure linear congruential generator (Park–Miller MINSTD),
-- | implemented with Schrage's algorithm so every intermediate product
-- | fits in a 32-bit Int. Determinism is the point: a game *is* its seed,
-- | so any game can be replayed or shared as a single integer.
module Kibitzer.Rng
  ( Seed
  , mkSeed
  , seedToInt
  , step
  , uniform
  , pick
  , shuffle
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))

newtype Seed = Seed Int

derive instance Eq Seed

instance Show Seed where
  show (Seed s) = "(Seed " <> show s <> ")"

-- MINSTD constants: modulus (a Mersenne prime), multiplier, and the
-- Schrage decomposition quotient/remainder (q = m / a, r = m mod a).
modulus :: Int
modulus = 2147483647

multiplier :: Int
multiplier = 48271

schrageQ :: Int
schrageQ = 44488

schrageR :: Int
schrageR = 3399

-- | Normalise any Int into the generator's state space [1, modulus - 1].
-- | PureScript's Euclidean `mod` never goes negative, so this is total.
mkSeed :: Int -> Seed
mkSeed n = Seed (1 + n `mod` (modulus - 1))

seedToInt :: Seed -> Int
seedToInt (Seed s) = s

step :: Seed -> Tuple Int Seed
step (Seed s) =
  let
    hi = s / schrageQ
    lo = s `mod` schrageQ
    next = multiplier * lo - schrageR * hi
    wrapped = if next <= 0 then next + modulus else next
  in
    Tuple wrapped (Seed wrapped)

-- | A value in [0, n). Plain modulus — the bias is negligible for the tiny
-- | ranges used here. Total for every n via `max 1 n`.
uniform :: Int -> Seed -> Tuple Int Seed
uniform n seed =
  let
    Tuple v seed' = step seed
  in
    Tuple (v `mod` max 1 n) seed'

-- | Uniform choice from a non-empty array. The index is in range by
-- | construction; the `fromMaybe` fallback merely satisfies totality.
pick :: forall a. NonEmptyArray a -> Seed -> Tuple a Seed
pick xs seed =
  let
    Tuple i seed' = uniform (NEA.length xs) seed
  in
    Tuple (fromMaybe (NEA.head xs) (NEA.index xs i)) seed'

-- | Fisher–Yates by repeated random extraction. Quadratic, but the deck
-- | has 21 cards; clarity wins.
shuffle :: forall a. Array a -> Seed -> Tuple (Array a) Seed
shuffle = go []
  where
  go :: Array a -> Array a -> Seed -> Tuple (Array a) Seed
  go acc remaining seed =
    let
      Tuple i seed' = uniform (Array.length remaining) seed
    in
      case Array.index remaining i of
        Nothing -> Tuple acc seed -- remaining is empty: done
        Just x ->
          go (Array.snoc acc x)
            (fromMaybe [] (Array.deleteAt i remaining))
            seed'
