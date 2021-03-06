module Check (checkSyntax) where

import Bag
import Control.Applicative
import Data.IORef
import DynFlags
import ErrUtils
import Exception
import FastString
import GHC
import HscTypes
import Outputable hiding (showSDoc)
import Pretty
import Types
import Prelude hiding (catch)

----------------------------------------------------------------

checkSyntax :: Options -> String -> IO String
checkSyntax _ file = unlines <$> check file

----------------------------------------------------------------

check :: String -> IO [String]
check fileName = withGHC $ do
    ref <- liftIO $ newIORef []
    initSession
    setTargetFile fileName
    loadWithLogger (refLogger ref) LoadAllTargets `gcatch` handleParseError ref
    clearWarnings
    liftIO $ readIORef ref
  where
    -- I don't know why, but parseDynamicFlags must be used.
    initSession = do
        dflags <- getSessionDynFlags
        (dflags',_,_) <- parseDynamicFlags dflags cmdOptions
        setSessionDynFlags $ setFlags dflags'
    setTargetFile file = do
        target <- guessTarget file Nothing
        setTargets [target]
    handleParseError ref e = do
        liftIO . writeIORef ref $ errBagToStrList . srcErrorMessages $ e
        return Succeeded

-- I don't know why, but parseDynamicFlags must be used.
cmdOptions :: [Located String]
cmdOptions = map noLoc ["-Wall","-fno-warn-unused-do-bind", "-fno-warn-missing-signatures"]

----------------------------------------------------------------

refLogger :: IORef [String] -> WarnErrLogger
refLogger ref Nothing =
    (errBagToStrList <$> getWarnings) >>= liftIO . writeIORef ref
refLogger ref (Just e) =
    liftIO . writeIORef ref $ errBagToStrList . srcErrorMessages $ e

errBagToStrList :: Bag ErrMsg -> [String]
errBagToStrList = map showErrMsg . reverse . bagToList

----------------------------------------------------------------

setFlags :: DynFlags -> DynFlags
setFlags d = d {
    importPaths = importPaths d ++ importDirs
  , packageFlags = ghcPackage : packageFlags d
  , ghcLink = NoLink
-- GHC.desugarModule does not produces the pattern warnings, why?
--  , hscTarget = HscNothing
  , hscTarget = HscInterpreted
  }

importDirs :: [String]
importDirs = ["..","../..","../../..","../../../../.."]

ghcPackage :: PackageFlag
ghcPackage = ExposePackage "ghc"

----------------------------------------------------------------

showErrMsg :: ErrMsg -> String
showErrMsg err = file ++ ":" ++ line ++ ":" ++ col ++ ":" ++ msg ++ "\0" ++ ext
   where
     spn = head (errMsgSpans err)
     file = unpackFS (srcSpanFile spn)
     line = show (srcSpanStartLine spn)
     col  = show (srcSpanStartCol spn)
     msg = showSDoc (errMsgShortDoc err)
     ext = showSDoc (errMsgExtraInfo err)

style :: PprStyle
style = mkUserStyle neverQualify AllTheWay

showSDoc :: SDoc -> String
showSDoc d = map toNull . Pretty.showDocWith ZigZagMode $ d style
  where
    toNull '\n' = '\0'
    toNull x = x
