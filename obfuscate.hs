#!/usr/bin/env stack
-- stack --resolver lts script

{-
 - stack build --dry-run # in <in-dir>
 - rm -rf <out-dir> && stack obfuscate.hs <in-dir> <out-dir> --ignore <pkg> && cp cabal.project <out-dir> && cp cabal.project.freeze <out-dir>
 -}

{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

import ClassyPrelude

import Control.Monad (fail)
import Data.Foldable (foldrM)
import Distribution.PackageDescription.Parsec (readGenericPackageDescription)
import Distribution.PackageDescription.PrettyPrint (writeGenericPackageDescription)
import Distribution.Types.Benchmark (Benchmark)
import Distribution.Types.BuildInfo (BuildInfo)
import Distribution.Types.CondTree (CondTree)
import Distribution.Types.Dependency (Dependency)
import Distribution.Types.Executable (Executable)
import Distribution.Types.GenericPackageDescription (GenericPackageDescription)
import Distribution.Types.Library (Library)
import Distribution.Types.PackageDescription (PackageDescription)
import Distribution.Types.PackageId (PackageIdentifier)
import Distribution.Types.PackageName (PackageName)
import Distribution.Types.TestSuite (TestSuite)
import Distribution.Types.UnqualComponentName (UnqualComponentName)
import Distribution.Version (mkVersion)
import System.Directory (createDirectory, doesDirectoryExist, listDirectory, pathIsSymbolicLink)
import System.FilePath.Posix (isExtensionOf, takeBaseName)
import System.Random (randomIO)

import qualified Data.Map as Map
import qualified Distribution.Types.Benchmark as Benchmark
import qualified Distribution.Types.BenchmarkInterface as BenchmarkInterface
import qualified Distribution.Types.BuildInfo as BuildInfo
import qualified Distribution.Types.CondTree as CondTree
import qualified Distribution.Types.Dependency as Dependency
import qualified Distribution.Types.Executable as Executable
import qualified Distribution.Types.GenericPackageDescription as GenericPackageDescription
import qualified Distribution.Types.Library as Library
import qualified Distribution.Types.PackageDescription as PackageDescription
import qualified Distribution.Types.PackageId as PackageId
import qualified Distribution.Types.PackageName as PackageName
import qualified Distribution.Types.TestSuite as TestSuite
import qualified Distribution.Types.TestSuiteInterface as TestSuiteInterface
import qualified Distribution.Types.UnqualComponentName as UnqualComponentName
import qualified Distribution.Verbosity as Verbosity
import qualified Options.Applicative as Opt

data Opts = Opts
  { optsInputDirectory :: FilePath
  , optsOutputDirectory :: FilePath
  , optsIgnores :: [String]
  }

listFilesRecursive :: FilePath -> IO (Set FilePath)
listFilesRecursive dir = do
  dirs <- listDirectory dir
  fmap mconcat . for dirs $ \case
    -- don't include "hidden" directories, i.e. those that start with a '.'
    '.' : _ -> pure mempty
    "dist-newstyle" -> pure mempty
    fn -> do
      let path = if dir == "." then fn else dir </> fn
      isDir <- doesDirectoryExist path
      isSymlink <- pathIsSymbolicLink path
      case (isSymlink, isDir) of
        (True, _) -> pure mempty
        (_, True) -> listFilesRecursive path
        _ -> pure $ setFromList [path]

parseCabalFile :: FilePath -> IO (PackageName, GenericPackageDescription)
parseCabalFile cabalFile = do
  genericPackageDescription <- readGenericPackageDescription Verbosity.silent cabalFile
  pure
    ( PackageId.pkgName . PackageDescription.package . GenericPackageDescription.packageDescription $ genericPackageDescription
    , genericPackageDescription
    )

newRandomName :: IO String
newRandomName = intercalate "-" . asList <$> replicateM 3 (replicateM 10 (toEnum . (+) 97 . flip mod 26 <$> randomIO))

newRandomPackageName :: IO PackageName
newRandomPackageName = PackageName.mkPackageName <$> newRandomName

newRandomUnqualName :: IO UnqualComponentName
newRandomUnqualName = UnqualComponentName.mkUnqualComponentName <$> newRandomName

sanitizeDependency :: Map PackageName PackageName -> Set PackageName -> Dependency -> [Dependency]
sanitizeDependency remap ignores dependency@(Dependency.Dependency name version library) =
  if member name ignores then [] else [Dependency.Dependency (findWithDefault name name remap) version library]

sanitizePackageIdentifier :: Map PackageName PackageName -> PackageIdentifier -> PackageIdentifier
sanitizePackageIdentifier remap identifier =
  let name = PackageId.pkgName identifier
  in identifier
    { PackageId.pkgName = findWithDefault name name remap
    , PackageId.pkgVersion = mkVersion [0, 0, 0, 0]
    }

sanitizePackageDescription :: Map PackageName PackageName -> PackageDescription -> PackageDescription
sanitizePackageDescription remap packageDescription = packageDescription
  { PackageDescription.package = sanitizePackageIdentifier remap $ PackageDescription.package packageDescription
  , PackageDescription.copyright = ""
  , PackageDescription.maintainer = ""
  , PackageDescription.author = ""
  , PackageDescription.synopsis = ""
  , PackageDescription.description = ""
  , PackageDescription.dataFiles = []
  , PackageDescription.extraSrcFiles = []
  , PackageDescription.extraTmpFiles = []
  , PackageDescription.extraDocFiles = []
  }

sanitizeBuildInfo :: Map PackageName PackageName -> Set PackageName -> BuildInfo -> BuildInfo
sanitizeBuildInfo remap ignores buildInfo = buildInfo
  { BuildInfo.buildTools = []
  , BuildInfo.buildToolDepends = []
  , BuildInfo.hsSourceDirs = []
  , BuildInfo.otherModules = []
  , BuildInfo.virtualModules = []
  , BuildInfo.autogenModules = []
  , BuildInfo.targetBuildDepends = foldMap (sanitizeDependency remap ignores) $ BuildInfo.targetBuildDepends buildInfo
  }

sanitizeLibrary :: Map PackageName PackageName -> Set PackageName -> CondTree a [Dependency] Library -> CondTree a [Dependency] Library
sanitizeLibrary remap ignores condTree =
  let library = CondTree.condTreeData condTree
  in condTree
    { CondTree.condTreeConstraints = foldMap (sanitizeDependency remap ignores) $ CondTree.condTreeConstraints condTree
    , CondTree.condTreeData = library
      { Library.exposedModules = []
      , Library.reexportedModules = []
      , Library.signatures = []
      , Library.libBuildInfo = sanitizeBuildInfo remap ignores $ Library.libBuildInfo library
      }
    }

sanitizeExecutable :: Map PackageName PackageName -> Set PackageName -> UnqualComponentName -> CondTree a [Dependency] Executable -> CondTree a [Dependency] Executable
sanitizeExecutable remap ignores name condTree =
  let executable = CondTree.condTreeData condTree
  in condTree
    { CondTree.condTreeConstraints = foldMap (sanitizeDependency remap ignores) $ CondTree.condTreeConstraints condTree
    , CondTree.condTreeData = executable
      { Executable.exeName = name
      , Executable.modulePath = "main.hs" -- we'll never actually reference this file, since we're just using this to run `cabal build all --dry-run`
      , Executable.buildInfo = sanitizeBuildInfo remap ignores $ Executable.buildInfo executable
      }
    }

sanitizeTestSuite :: Map PackageName PackageName -> Set PackageName -> UnqualComponentName -> CondTree a [Dependency] TestSuite -> CondTree a [Dependency] TestSuite
sanitizeTestSuite remap ignores name condTree =
  let test = CondTree.condTreeData condTree
  in condTree
    { CondTree.condTreeConstraints = foldMap (sanitizeDependency remap ignores) $ CondTree.condTreeConstraints condTree
    , CondTree.condTreeData = test
      { TestSuite.testName = name
      , TestSuite.testInterface = TestSuiteInterface.TestSuiteExeV10 (mkVersion [1, 0]) "main.hs"
      , TestSuite.testBuildInfo = sanitizeBuildInfo remap ignores $ TestSuite.testBuildInfo test
      }
    }

sanitizeBenchmark :: Map PackageName PackageName -> Set PackageName -> UnqualComponentName -> CondTree a [Dependency] Benchmark -> CondTree a [Dependency] Benchmark
sanitizeBenchmark remap ignores name condTree =
  let benchmark = CondTree.condTreeData condTree
  in condTree
    { CondTree.condTreeConstraints = foldMap (sanitizeDependency remap ignores) $ CondTree.condTreeConstraints condTree
    , CondTree.condTreeData = benchmark
      { Benchmark.benchmarkName = name
      , Benchmark.benchmarkInterface = BenchmarkInterface.BenchmarkExeV10 (mkVersion [1, 0]) "main.hs"
      , Benchmark.benchmarkBuildInfo = sanitizeBuildInfo remap ignores $ Benchmark.benchmarkBuildInfo benchmark
      }
    }

sanitizeGenericPackageDescription :: Map PackageName PackageName -> Set PackageName -> GenericPackageDescription -> IO GenericPackageDescription
sanitizeGenericPackageDescription remap ignores genericPackageDescription = do
  libraries <- for (GenericPackageDescription.condSubLibraries genericPackageDescription) $ \(name, condTree) -> do
    newName <- newRandomUnqualName
    pure (newName, sanitizeLibrary remap ignores condTree)
  executables <- for (GenericPackageDescription.condExecutables genericPackageDescription) $ \(name, condTree) -> do
    newName <- newRandomUnqualName
    pure (newName, sanitizeExecutable remap ignores newName condTree)
  tests <- for (GenericPackageDescription.condTestSuites genericPackageDescription) $ \(name, condTree) -> do
    newName <- newRandomUnqualName
    pure (newName, sanitizeTestSuite remap ignores newName condTree)
  benchmarks <- for (GenericPackageDescription.condBenchmarks genericPackageDescription) $ \(name, condTree) -> do
    newName <- newRandomUnqualName
    pure (newName, sanitizeBenchmark remap ignores newName condTree)
  pure genericPackageDescription
    { GenericPackageDescription.packageDescription = sanitizePackageDescription remap $ GenericPackageDescription.packageDescription genericPackageDescription
    , GenericPackageDescription.condLibrary = map (sanitizeLibrary remap ignores) $ GenericPackageDescription.condLibrary genericPackageDescription
    , GenericPackageDescription.condSubLibraries = libraries
    , GenericPackageDescription.condForeignLibs = []
    , GenericPackageDescription.condExecutables = executables
    , GenericPackageDescription.condTestSuites = tests
    , GenericPackageDescription.condBenchmarks = benchmarks
    }

randomizePackages :: Map PackageName GenericPackageDescription -> Set PackageName -> IO (Map PackageName GenericPackageDescription)
randomizePackages packages ignores = do
  let oldPackageNames = Map.keys packages
  remappedPackageNames <- mapFromList <$> for oldPackageNames (\package -> (package,) <$> newRandomPackageName)
  let remapPackageName (oldName, newName) accum = do
        oldPackage <- maybe (fail $ show oldName <> " not found in packages") pure $ lookup oldName packages
        pure
          . insertMap newName oldPackage
          . deleteMap oldName
          $ accum
  remappedPackagesWithOldDependencies <- foldrM remapPackageName mempty $ mapToList remappedPackageNames
  for remappedPackagesWithOldDependencies $ sanitizeGenericPackageDescription remappedPackageNames ignores

writePackages :: FilePath -> Map PackageName GenericPackageDescription -> IO ()
writePackages outputDirectory packages =
  for_ (mapToList packages) $ \(packageName, genericPackageDescription) -> do
    let dir = outputDirectory </> PackageName.unPackageName packageName
        file = dir </> PackageName.unPackageName packageName <.> "cabal"
    createDirectory dir
    writeGenericPackageDescription file genericPackageDescription

parseArgs :: IO Opts
parseArgs = Opt.execParser (Opt.info (Opt.helper <*> parser) $ Opt.progDesc "Obfuscate a directory containing cabal packages")
  where
    parser = Opts
      <$> Opt.strArgument (Opt.metavar "INPUT_DIR")
      <*> Opt.strArgument (Opt.metavar "OUTPUT_DIR")
      <*> many (Opt.strOption (Opt.metavar "PACKAGE" <> Opt.long "ignore" <> Opt.help "Package to ignore"))

main :: IO ()
main = do
  Opts {..} <- parseArgs
  whenM (doesDirectoryExist optsOutputDirectory) $ fail "Output dir shouldn't exist"
  putStrLn "Creating output directory"
  createDirectory optsOutputDirectory
  putStrLn "Finding project cabal files"
  projectPackageCabalFiles <- filter (not . flip elem optsIgnores . takeBaseName) . filter (isExtensionOf ".cabal") . setToList <$> listFilesRecursive optsInputDirectory
  putStrLn $ "Parsing " <> tshow (length projectPackageCabalFiles) <> " cabal files"
  oldPackages <- mapFromList <$> for projectPackageCabalFiles parseCabalFile
  putStrLn "Randomizing packages"
  newPackages <- randomizePackages oldPackages (setFromList $ PackageName.mkPackageName <$> optsIgnores)
  putStrLn "Writing output"
  writePackages optsOutputDirectory newPackages
