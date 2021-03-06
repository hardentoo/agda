{-# LANGUAGE BangPatterns  #-}
{-# LANGUAGE CPP           #-}

module Agda.TypeChecking.Rules.LHS.ProblemRest where

#if __GLASGOW_HASKELL__ <= 708
import Data.Functor ( (<$), (<$>) )
#endif

import Control.Arrow (first, second)


import Agda.Syntax.Common
import Agda.Syntax.Internal
import Agda.Syntax.Abstract.Pattern
import qualified Agda.Syntax.Abstract as A

import Agda.TypeChecking.Monad
import Agda.TypeChecking.Pretty
import Agda.TypeChecking.Telescope
import Agda.TypeChecking.Substitute

import Agda.TypeChecking.Rules.LHS.Problem
import Agda.TypeChecking.Rules.LHS.Implicit

import Agda.Utils.Functor
import Agda.Utils.List
import Agda.Utils.Size
import Agda.Utils.Permutation

#include "undefined.h"
import Agda.Utils.Impossible

-- | Rename the variables in a telescope using the names from a given pattern.
--
--   Precondition: we have at least as many patterns as entries in the telescope.
--
useNamesFromPattern :: [NamedArg A.Pattern] -> Telescope -> Telescope
useNamesFromPattern ps tel
  | size tel > length ps = __IMPOSSIBLE__
  | otherwise            = telFromList $ zipWith ren ps $ telToList tel
  where
    ren (Arg ai (Named nm p)) dom@(Dom info finite (y, a)) =
      case p of
        -- Andreas, 2017-10-12, issue #2803, also preserve user-written hidden names.
        -- However, not if the argument is named, because then the name in the telescope
        -- is significant for implicit insertion.
        A.VarP (A.BindName x)
          | not (isNoName x)
          , visible info || (getOrigin ai == UserWritten && nm == Nothing) ->
          Dom info finite (nameToArgName x, a)
        A.AbsurdP{} | visible info -> Dom info finite (stringToArgName "()", a)
        A.PatternSynP{} -> __IMPOSSIBLE__  -- ensure there are no syns left
        -- Andreas, 2016-05-10, issue 1848: if context variable has no name, call it "x"
        _ | visible info && isNoName y -> Dom info finite (stringToArgName "x", a)
          | otherwise                  -> dom

useOriginFrom :: (LensOrigin a, LensOrigin b) => [a] -> [b] -> [a]
useOriginFrom = zipWith $ \x y -> setOrigin (getOrigin y) x

-- | Are there any untyped user patterns left?
noProblemRest :: Problem -> Bool
noProblemRest (Problem _ _ _ (ProblemRest ps _)) = null ps

-- | Construct an initial 'split' 'Problem' from user patterns.
--   Example:
--   @
--
--      Case : {A : Set} → Maybe A → Set → Set → Set
--      Case nothing  B C = B
--      Case (just _) B C = C
--
--      sample : {A : Set} (m : Maybe A) → Case m Bool (Maybe A → Bool)
--      sample (just a) (just b) = true
--      sample (just a) nothing  = false
--      sample nothing           = true
--   @
--   The problem generated for the first clause of @sample@
--   with patterns @just a, just b@ would be:
--   @
--      problemInPat  = ["_", "just a"]
--      problemOutPat = ["A", "m"]
--      problemTel    = [A : Set, m : Maybe A]
--      problemRest   =
--        restPats    = ["just b"]
--        restType    = "Case m Bool (Maybe A -> Bool)"
--   @

problemFromPats :: [NamedArg A.Pattern] -- ^ The user patterns.
  -> Type            -- ^ The type the user patterns eliminate.
  -> TCM Problem     -- ^ The initial problem constructed from the user patterns.
problemFromPats ps0 a = do
  -- Andreas, 2017-01-18, issue #819: We set all A.WildP origins to Inserted
  -- in order to guide the pattern printer to discard variable names it made up.
  let ps = (`mapNamedArgPattern` ps0) $ \case
        p | A.WildP{} <- namedArg p -> setOrigin Inserted p
        p -> p
  -- For the initial problem, do not insert trailing implicits.
  -- This has the effect of not including trailing hidden domains in the problem telescope.
  -- In all later call to insertImplicitPatterns, we can then use ExpandLast.
  -- Ulf, 2016-04-25: Actually we do need to ExpandLast because where blocks
  -- need the implicits.
  ps <- insertImplicitPatternsT ExpandLast ps a
  reportSDoc "tc.lhs.imp" 20 $
    text "insertImplicitPatternsT returned" <+> fsep (map prettyA ps)

  -- Redo the telView, in order to *not* normalize the clause type further than necessary.
  -- (See issue 734.)
  TelV tel0 b  <- telViewUpToPath (length ps) a
  let gamma     = useNamesFromPattern ps tel0
      as        = telToList gamma
      (ps1,ps2) = splitAt (size as) ps
      -- now (gamma -> b) = a and |gamma| = |ps1|
      pr        = ProblemRest ps2 $ defaultArg b

      -- internal patterns start as all variables
  let ips = teleNamedArgs gamma `useOriginFrom` ps

      -- the initial problem for starting the splitting
      problem  = Problem ps1 ips gamma pr :: Problem
  reportSDoc "tc.lhs.problem" 10 $
    vcat [ text "checking lhs -- generated an initial split problem:"
         , nest 2 $ vcat
           [ text "ps    =" <+> fsep (map prettyA ps)
           , text "a     =" <+> prettyTCM a
           , text "xs    =" <+> text (show $ map (fst . unDom) as)
           , text "ps1   =" <+> fsep (map prettyA ps1)
        -- , text "ips   =" <+> prettyTCM ips  -- no prettyTCM instance
           , text "gamma =" <+> prettyTCM gamma
           , text "ps2   =" <+> fsep (map prettyA ps2)
           , text "b     =" <+> addContext gamma (prettyTCM b)
           ]
         ]
  return problem

-- | Try to move patterns from the problem rest into the problem.
--   Possible if type of problem rest has been updated to a function type.
updateProblemRest_ :: Problem -> TCM (Nat, Problem)
updateProblemRest_ p@(Problem ps0 qs0 tel0 (ProblemRest ps a)) = do
      ps <- insertImplicitPatternsT ExpandLast ps $ unArg a
      reportSDoc "tc.lhs.imp" 20 $
        text "insertImplicitPatternsT returned" <+> fsep (map prettyA ps)
      -- (Issue 734: Do only the necessary telView to preserve clause types as much as possible.)
      TelV tel b   <- telViewUpToPath (length ps) $ unArg a
      let gamma     = useNamesFromPattern ps tel
          n         = size gamma
          (ps1,ps2) = splitAt n ps
          tel1      = telFromList $ telToList tel0 ++ telToList gamma
          pr        = ProblemRest ps2 (a $> b)
          qs1       = teleNamedArgs gamma `useOriginFrom` ps
      reportSDoc "tc.lhs.problem" 10 $ addContext tel0 $ vcat
        [ text "checking lhs -- updated split problem:"
        , nest 2 $ vcat
          [ text "ps    =" <+> fsep (map prettyA ps)
          , text "a     =" <+> prettyTCM a
          , text "tel   =" <+> prettyTCM tel
          , text "gamma =" <+> prettyTCM gamma
          , text "ps1   =" <+> fsep (map prettyA ps1)
          , text "ps2   =" <+> fsep (map prettyA ps2)
          , text "b     =" <+> addContext gamma (prettyTCM b)
          ]
        ]
      return $ (n,) $ Problem (ps0 ++ ps1) (applySubst (raiseS n) qs0 ++ qs1) tel1 pr

updateProblemRest :: LHSState -> TCM LHSState
updateProblemRest st@LHSState { lhsProblem = p } = do
  (n, p') <- updateProblemRest_ p
  if (n == 0) then return st else do
    let tau = raiseS n
    return $ LHSState
      { lhsProblem = p'
      , lhsDPI     = applyPatSubst tau (lhsDPI st)
      , lhsPartialSplit = lhsPartialSplit st
      , lhsShouldBeEmptyTypes = map (second $ applyPatSubst tau) (lhsShouldBeEmptyTypes st)
      }
