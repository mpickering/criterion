module Criterion.Main
    (
      module Criterion
    , defaultMain
    , defaultOptions
    , parseCommandLine
    ) where

import Control.Exception (evaluate)
import Data.Char (toLower)
import Data.List (isPrefixOf)
import Data.Map (fromList, lookup)
import Data.Set (singleton)
import Control.Monad
import Criterion
import Criterion.Config
import Criterion.Types
import System.Console.GetOpt
import System.IO
import System.Environment
import System.Exit
import Prelude hiding (lookup)

plot :: (PlotType -> Plot) -> String -> IO Config
plot f s = case lookup s m of
             Nothing -> parseError "unknown plot type"
             Just t  -> return mempty { cfgPlot = singleton (f t) }
  where m = fromList $ ("win", Window) :
            [(map toLower (show t),t) | t <- [minBound..maxBound]]

ci :: String -> IO Config
ci s = case reads s' of
         [(d,"%")] -> check (d/100)
         [(d,"")]  -> check d
         _         -> parseError "invalid confidence interval provided"
  where s' = case s of
               ('.':_) -> '0':s
               _       -> s
        check d | d <= 0 = parseError "confidence interval is negative"
                | d >= 1 = parseError "confidence interval is greater than 1"
                | otherwise = return mempty { cfgConfInterval = ljust d }

pos :: (Num a, Ord a, Read a) =>
       String -> (Last a -> Config) -> String -> IO Config
pos q f s =
    case reads s of
      [(n,"")] | n > 0     -> return . f $ ljust n
               | otherwise -> parseError $ q ++ " must be positive"
      _                    -> parseError $ "invalid " ++ q ++ " provided"

parseError :: String -> IO a
parseError msg = do
  p <- getProgName
  hPutStrLn stderr $ "Error: " ++ msg
  hPutStrLn stderr $ "Run \"" ++ p ++ " --help\" for usage information"
  exitWith (ExitFailure 64)

noArg :: Config -> ArgDescr (IO Config)
noArg = NoArg . return

defaultOptions :: [OptDescr (IO Config)]
defaultOptions = [
   Option ['h','?'] ["help"] (noArg mempty { cfgPrintExit = Help })
          "print help, then exit"
 , Option ['G'] ["no-gc"] (noArg mempty { cfgPerformGC = ljust False })
          "do not collect garbage between iterations"
 , Option ['g'] ["gc"] (noArg mempty { cfgPerformGC = ljust True })
          "collect garbage between iterations"
 , Option ['I'] ["ci"] (ReqArg ci "CI")
          "bootstrap confidence interval"
 , Option ['k'] ["plot-kde"] (ReqArg (plot KernelDensity) "TYPE")
          "plot kernel density"
 , Option ['q'] ["quiet"] (noArg mempty { cfgVerbosity = Quiet })
          "print less output"
 , Option [] ["resamples"]
          (ReqArg (pos "resample count"$ \n -> mempty { cfgResamples = n }) "N")
          "number of bootstrap resamples to perform"
 , Option [] ["samples"]
          (ReqArg (pos "sample count" $ \n -> mempty { cfgSamples = n }) "N")
          "number of samples to collect"
 , Option ['t'] ["plot-timing"] (ReqArg (plot Timing) "TYPE")
          "plot timings"
 , Option ['V'] ["version"] (noArg mempty { cfgPrintExit = Version })
          "display version, then exit"
 , Option ['v'] ["verbose"] (noArg mempty { cfgVerbosity = Verbose })
          "print more output"
 ]

printBanner :: Config -> IO ()
printBanner cfg =
    case cfgBanner cfg of
      Last (Just b) -> hPutStrLn stdout b
      _             -> hPutStrLn stdout "hi mom!"

printUsage :: [OptDescr (IO Config)] -> ExitCode -> IO a
printUsage options exitCode = do
  p <- getProgName
  putStr (usageInfo ("Usage: " ++ p ++ " [OPTIONS]") options)
  exitWith exitCode

parseCommandLine :: [OptDescr (IO Config)] -> [String] -> IO (Config, [String])
parseCommandLine options args =
  case getOpt Permute options args of
    (_, _, (err:_)) -> parseError err
    (opts, rest, _) -> do
      cfg <- (mappend defaultConfig . mconcat) `fmap` sequence opts
      case cfgPrintExit cfg of
        Help ->    printBanner cfg >> printUsage options ExitSuccess
        Version -> printBanner cfg >> exitWith ExitSuccess
        _ ->       return (cfg, rest)

defaultMain :: [Benchmark] -> IO ()
defaultMain bs = do
  (cfg, args) <- parseCommandLine defaultOptions =<< getArgs
  env <- sampleEnvironment cfg
  let shouldRun b = null args || any (`isPrefixOf` b) args
  forM_ bs $ \b -> when (shouldRun . benchName $ b) $ do
                     runBenchmark cfg env b
                     return ()
