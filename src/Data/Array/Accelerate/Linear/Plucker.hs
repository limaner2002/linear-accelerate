{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# LANGUAGE ViewPatterns          #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# OPTIONS_GHC -fno-warn-orphans        #-}
-----------------------------------------------------------------------------
-- |
-- Module      : Data.Array.Accelerate.Linear.Plucker
-- Copyright   : 2014 Edward Kmett, Charles Durham,
--               [2015..2018] Trevor L. McDonell
-- License     : BSD-style (see the file LICENSE)
--
-- Maintainer  : Edward Kmett <ekmett@gmail.com>
-- Stability   : experimental
-- Portability : non-portable
--
-- Plücker coordinates for lines in 3d homogeneous space.
----------------------------------------------------------------------------

module Data.Array.Accelerate.Linear.Plucker (

  Plucker(..),

  squaredError,
  isotropic,
  (><),
  plucker,
  plucker3D,

  -- * operations on lines
  LinePass(..),
  parallel,
  intersects,
  passes,
  quadranceToOrigin,
  closestToOrigin,
  isLine,

  -- * Basis elements
       p01, p02, p03,
  p10,      p12, p13,
  p20, p21,      p23,
  p30, p31, p32,

) where

import Data.Array.Accelerate                    hiding ( fromInteger )
import Data.Array.Accelerate.Data.Functor
import Data.Array.Accelerate.Smart
import Data.Array.Accelerate.Product
import Data.Array.Accelerate.Array.Sugar

import Data.Array.Accelerate.Linear.Epsilon
import Data.Array.Accelerate.Linear.Lift
import Data.Array.Accelerate.Linear.Metric
import Data.Array.Accelerate.Linear.V2
import Data.Array.Accelerate.Linear.V3
import Data.Array.Accelerate.Linear.V4
import Data.Array.Accelerate.Linear.Vector

import Control.Lens
import Data.Function
import Data.Typeable
import Linear.Plucker                           ( Plucker(..), LinePass(..) )
import Prelude                                  ( fromInteger )
import qualified Linear.Plucker                 as L
import qualified Prelude                        as P


-- | Valid Plücker coordinates @p@ will have @'squaredError' p '==' 0@
--
-- That said, floating point makes a mockery of this claim, so you may want to
-- use 'nearZero'.
--
squaredError :: forall a. Num a => Exp (Plucker a) -> Exp a
squaredError = lift1 (L.squaredError :: Plucker (Exp a) -> Exp a)

-- | This isn't the actual metric because this bilinear form gives rise to an
-- isotropic quadratic space.
--
infixl 5 ><
(><) :: forall a. Num a => Exp (Plucker a) -> Exp (Plucker a) -> Exp a
(><) = lift2 ((L.><) :: Plucker (Exp a) -> Plucker (Exp a) -> Exp a)

-- | Checks if the line is near-isotropic (isotropic vectors in this quadratic
-- space represent lines in real 3D space).
--
isotropic :: Epsilon a => Exp (Plucker a) -> Exp Bool
isotropic a = nearZero (a >< a)

-- | Given a pair of points represented by homogeneous coordinates generate
-- Plücker coordinates for the line through them, directed from the second
-- towards the first.
--
plucker :: forall a. Num a => Exp (V4 a) -> Exp (V4 a) -> Exp (Plucker a)
plucker = lift2 (L.plucker :: V4 (Exp a) -> V4 (Exp a) -> Plucker (Exp a))

-- | Given a pair of 3D points, generate Plücker coordinates for the line
-- through them, directed from the second towards the first.
--
plucker3D :: forall a. Num a => Exp (V3 a) -> Exp (V3 a) -> Exp (Plucker a)
plucker3D = lift2 (L.plucker3D :: V3 (Exp a) -> V3 (Exp a) -> Plucker (Exp a))

-- | Checks if two lines intersect (or nearly intersect).
--
intersects :: (Epsilon a, Ord a) => Exp (Plucker a) -> Exp (Plucker a) -> Exp Bool
intersects a b = not (a `parallel` b) && passes a b == constant Coplanar

-- | Check how two lines pass each other. @passes l1 l2@ describes @l2@ when
-- looking down @l1@.
--
passes :: (Epsilon a, Ord a) => Exp (Plucker a) -> Exp (Plucker a) -> Exp LinePass
passes a b =
  if nearZero s then constant Coplanar else
  if s > 0      then constant Counterclockwise
                else constant Clockwise
  where
    s        = (lift u1 `dot` lift v2) + (lift u2 `dot` lift v1)
    V2 u1 v1 = toUV a
    V2 u2 v2 = toUV b

-- | Checks if two lines are parallel.
--
parallel :: Epsilon a => Exp (Plucker a) -> Exp (Plucker a) -> Exp Bool
parallel a b = nearZero $ lift u1 `cross` lift u2
  where
    V2 u1 _ = toUV a
    V2 u2 _ = toUV b

-- | Represent a Plücker coordinate as a pair of 3-tuples, typically denoted
-- U and V.
--
toUV :: Elt a => Exp (Plucker a) -> V2 (V3 (Exp a))
toUV (unlift -> Plucker a b c d e f) = V2 (V3 a b c) (V3 d e f)

-- | The minimum squared distance of a line from the origin.
--
quadranceToOrigin :: Fractional a => Exp (Plucker a) -> Exp a
quadranceToOrigin p = (lift v `dot` lift v) / (lift u `dot` lift u)
  where
    V2 u v = toUV p

-- | The point where a line is closest to the origin.
--
closestToOrigin :: Fractional a => Exp (Plucker a) -> Exp (V3 a)
closestToOrigin p = normalizePoint . lift $ V4 x y z (lift u `dot` lift u)
  where
    V2 u v   = toUV p
    V3 x y z = unlift $ lift v `cross` lift u

-- | Not all 6-dimensional points correspond to a line in 3D. This predicate
-- tests that a Plücker coordinate lies on the Grassmann manifold, and does
-- indeed represent a 3D line.
--
isLine :: Epsilon a => Exp (Plucker a) -> Exp Bool
isLine p = nearZero $ lift u `dot` lift v
  where
    V2 u v = toUV p


-- | These elements form a basis for the Plücker space, or the Grassmanian
-- manifold @Gr(2,V4)@.
--
-- @
-- 'p01' :: 'Lens'' ('Plucker' a) a
-- 'p02' :: 'Lens'' ('Plucker' a) a
-- 'p03' :: 'Lens'' ('Plucker' a) a
-- 'p23' :: 'Lens'' ('Plucker' a) a
-- 'p31' :: 'Lens'' ('Plucker' a) a
-- 'p12' :: 'Lens'' ('Plucker' a) a
-- @
--
p01, p02, p03, p23, p31, p12 :: Elt a => Lens' (Exp (Plucker a)) (Exp a)
p01 = liftLens (L.p01 :: Lens' (Plucker (Exp a)) (Exp a))
p02 = liftLens (L.p02 :: Lens' (Plucker (Exp a)) (Exp a))
p03 = liftLens (L.p03 :: Lens' (Plucker (Exp a)) (Exp a))
p23 = liftLens (L.p23 :: Lens' (Plucker (Exp a)) (Exp a))
p31 = liftLens (L.p31 :: Lens' (Plucker (Exp a)) (Exp a))
p12 = liftLens (L.p12 :: Lens' (Plucker (Exp a)) (Exp a))

-- | These elements form an alternate basis for the Plücker space, or the
-- Grassmanian manifold @Gr(2,V4)@.
--
-- @
-- 'p10' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- 'p20' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- 'p30' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- 'p32' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- 'p13' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- 'p21' :: 'Num' a => 'Lens'' ('Plucker' a) a
-- @
--
p10, p20, p30, p32, p13, p21 :: Num a => Lens' (Exp (Plucker a)) (Exp a)
p10 = anti p01
p20 = anti p02
p30 = anti p03
p32 = anti p23
p13 = anti p31
p21 = anti p21

anti :: (P.Functor f, Num a) => ((Exp a -> f (Exp a)) -> r) -> (Exp a -> f (Exp a)) -> r
anti k f = k (P.fmap negate . f . negate)


-- Instances
-- ---------

deriving instance Typeable Plucker

instance Metric Plucker
instance Additive Plucker

instance Elt a => Elt (Plucker a) where
  type EltRepr (Plucker a) = EltRepr (a, a, a, a, a, a)
  eltType = eltType @(a, a, a, a, a, a)
  toElt p = let (x, y, z, w, u, v) = toElt p in Plucker x y z w u v
  fromElt (Plucker x y z w u v) = fromElt (x, y, z, w, u, v)

instance cst a => IsProduct cst (Plucker a) where
  type ProdRepr (Plucker a) = ProdRepr (a, a, a, a, a, a)
  fromProd (Plucker x y z w u v) = fromProd @cst (x, y, z, w, u, v)
  toProd p = let (x, y, z, w, u, v) = toProd @cst p in Plucker x y z w u v
  prod = prod @cst @(a, a, a, a, a, a)

instance (Lift Exp a, Elt (Plain a)) => Lift Exp (Plucker a) where
  type Plain (Plucker a) = Plucker (Plain a)
  -- lift = Exp . Tuple . F.foldl SnocTup NilTup
  lift (Plucker x y z w u v) =
    Exp $ Tuple $
      NilTup `SnocTup` lift x
             `SnocTup` lift y
             `SnocTup` lift z
             `SnocTup` lift w
             `SnocTup` lift u
             `SnocTup` lift v

instance Elt a => Unlift Exp (Plucker (Exp a)) where
  unlift t = Plucker
    (Exp $ SuccTupIdx (SuccTupIdx (SuccTupIdx (SuccTupIdx (SuccTupIdx ZeroTupIdx)))) `Prj` t)
    (Exp $ SuccTupIdx (SuccTupIdx (SuccTupIdx (SuccTupIdx ZeroTupIdx))) `Prj` t)
    (Exp $ SuccTupIdx (SuccTupIdx (SuccTupIdx ZeroTupIdx)) `Prj` t)
    (Exp $ SuccTupIdx (SuccTupIdx ZeroTupIdx) `Prj` t)
    (Exp $ SuccTupIdx ZeroTupIdx `Prj` t)
    (Exp $ ZeroTupIdx `Prj` t)

instance (Elt a, Elt b) => Each (Exp (Plucker a)) (Exp (Plucker b)) (Exp a) (Exp b) where
  each = liftLens (each :: Traversal (Plucker (Exp a)) (Plucker (Exp b)) (Exp a) (Exp b))

instance Eq a => Eq (Plucker a) where
  (==) = (==) `on` t6
  (/=) = (/=) `on` t6

instance Ord a => Ord (Plucker a) where
  (<)  = (<) `on` t6
  (>)  = (>) `on` t6
  (<=) = (<=) `on` t6
  (>=) = (>=) `on` t6
  min  = pl $$ on min t6
  max  = pl $$ on max t6

t6 :: Elt a => Exp (Plucker a) -> Exp (a,a,a,a,a,a)
t6 (unlift -> Plucker a b c d e f) = tup6 (a,b,c,d,e,f)

pl :: Elt a => Exp (a,a,a,a,a,a) -> Exp (Plucker a)
pl (untup6 -> (a,b,c,d,e,f)) = lift (Plucker a b c d e f)

instance Num a => P.Num (Exp (Plucker a)) where
  (+)           = lift2 ((+) :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  (-)           = lift2 ((-) :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  (*)           = lift2 ((*) :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  negate        = fmap negate
  abs           = fmap abs
  signum        = fmap signum
  fromInteger x = lift (P.fromInteger x :: Plucker (Exp a))

instance Fractional a => P.Fractional (Exp (Plucker a)) where
  recip          = fmap recip
  (/)            = lift2 ((/) :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  fromRational x = lift (P.fromRational x :: Plucker (Exp a))

instance Floating a => P.Floating (Exp (Plucker a)) where
  pi      = lift (pi :: Plucker (Exp a))
  exp     = fmap exp
  sqrt    = fmap sqrt
  log     = fmap log
  (**)    = lift2 ((**) :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  logBase = lift2 (logBase :: Plucker (Exp a) -> Plucker (Exp a) -> Plucker (Exp a))
  sin     = fmap sin
  tan     = fmap tan
  cos     = fmap cos
  asin    = fmap asin
  atan    = fmap atan
  acos    = fmap acos
  sinh    = fmap sinh
  tanh    = fmap tanh
  cosh    = fmap cosh
  asinh   = fmap asinh
  atanh   = fmap atanh
  acosh   = fmap acosh

instance Epsilon a => Epsilon (Plucker a) where
  nearZero = nearZero . quadrance

instance Functor Plucker where
  fmap g (unlift -> Plucker a b c d e f) = lift (Plucker (g a) (g b) (g c) (g d) (g e) (g f))
  x <$ _                                 = lift (Plucker x x x x x x)


instance Elt LinePass where
  type EltRepr LinePass = Int8

  eltType = eltType @Int8

  toElt x = let (==) = (P.==)   -- -XRebindableSyntax hax
            in  case x of
                  0 -> Coplanar
                  1 -> Clockwise
                  2 -> Counterclockwise
                  _ -> P.error "LinePass: unhandled constructor"

  fromElt Coplanar         = 0
  fromElt Clockwise        = 1
  fromElt Counterclockwise = 2

instance Eq LinePass where
  x == y = bitcast x == (bitcast y :: Exp Int8)
  x /= y = bitcast x /= (bitcast y :: Exp Int8)

