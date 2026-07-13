-- | The deck: six suspects, six weapons, nine rooms — 21 cards in all.
-- | Three go in the envelope (one per category); the remaining 18 are dealt.
module Kibitzer.Cards
  ( Suspect(..)
  , Weapon(..)
  , Room(..)
  , Card(..)
  , Category(..)
  , nonEmptySuspects
  , nonEmptyWeapons
  , nonEmptyRooms
  , allSuspects
  , allWeapons
  , allRooms
  , allCards
  , allCategories
  , cardCategory
  , cardsIn
  , suspectName
  , weaponName
  , roomName
  , displayName
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Generic.Rep (class Generic)
import Data.Set (Set)
import Data.Set as Set
import Data.Show.Generic (genericShow)

data Suspect = Scarlett | Mustard | White | Green | Peacock | Plum

derive instance Eq Suspect
derive instance Ord Suspect
derive instance Generic Suspect _

instance Show Suspect where
  show = genericShow

data Weapon = Candlestick | Knife | LeadPipe | Revolver | Rope | Wrench

derive instance Eq Weapon
derive instance Ord Weapon
derive instance Generic Weapon _

instance Show Weapon where
  show = genericShow

data Room
  = Kitchen
  | Ballroom
  | Conservatory
  | DiningRoom
  | BilliardRoom
  | Library
  | Lounge
  | Hall
  | Study

derive instance Eq Room
derive instance Ord Room
derive instance Generic Room _

instance Show Room where
  show = genericShow

data Card
  = SuspectCard Suspect
  | WeaponCard Weapon
  | RoomCard Room

derive instance Eq Card
derive instance Ord Card
derive instance Generic Card _

instance Show Card where
  show = genericShow

data Category = Suspects | Weapons | Rooms

derive instance Eq Category
derive instance Ord Category
derive instance Generic Category _

instance Show Category where
  show = genericShow

-- Non-empty by construction: `cons'` puts one element beyond doubt, so
-- random selection (`Rng.pick`) needs no impossible-case handling.

nonEmptySuspects :: NonEmptyArray Suspect
nonEmptySuspects = NEA.cons' Scarlett [ Mustard, White, Green, Peacock, Plum ]

nonEmptyWeapons :: NonEmptyArray Weapon
nonEmptyWeapons = NEA.cons' Candlestick [ Knife, LeadPipe, Revolver, Rope, Wrench ]

nonEmptyRooms :: NonEmptyArray Room
nonEmptyRooms = NEA.cons' Kitchen
  [ Ballroom, Conservatory, DiningRoom, BilliardRoom, Library, Lounge, Hall, Study ]

allSuspects :: Array Suspect
allSuspects = NEA.toArray nonEmptySuspects

allWeapons :: Array Weapon
allWeapons = NEA.toArray nonEmptyWeapons

allRooms :: Array Room
allRooms = NEA.toArray nonEmptyRooms

allCards :: Array Card
allCards =
  map SuspectCard allSuspects
    <> map WeaponCard allWeapons
    <> map RoomCard allRooms

allCategories :: Array Category
allCategories = [ Suspects, Weapons, Rooms ]

cardCategory :: Card -> Category
cardCategory = case _ of
  SuspectCard _ -> Suspects
  WeaponCard _ -> Weapons
  RoomCard _ -> Rooms

cardsIn :: Category -> Set Card
cardsIn category =
  Set.fromFoldable case category of
    Suspects -> map SuspectCard allSuspects
    Weapons -> map WeaponCard allWeapons
    Rooms -> map RoomCard allRooms

suspectName :: Suspect -> String
suspectName = case _ of
  Scarlett -> "Miss Scarlett"
  Mustard -> "Colonel Mustard"
  White -> "Mrs. White"
  Green -> "Rev. Green"
  Peacock -> "Mrs. Peacock"
  Plum -> "Professor Plum"

weaponName :: Weapon -> String
weaponName = case _ of
  Candlestick -> "Candlestick"
  Knife -> "Knife"
  LeadPipe -> "Lead Pipe"
  Revolver -> "Revolver"
  Rope -> "Rope"
  Wrench -> "Wrench"

roomName :: Room -> String
roomName = case _ of
  Kitchen -> "Kitchen"
  Ballroom -> "Ballroom"
  Conservatory -> "Conservatory"
  DiningRoom -> "Dining Room"
  BilliardRoom -> "Billiard Room"
  Library -> "Library"
  Lounge -> "Lounge"
  Hall -> "Hall"
  Study -> "Study"

displayName :: Card -> String
displayName = case _ of
  SuspectCard s -> suspectName s
  WeaponCard w -> weaponName w
  RoomCard r -> roomName r
