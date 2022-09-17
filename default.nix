let
  sources = import ./nix/sources.nix {};

  haskellNix = import sources.haskellNix {};
  pkgs = import
    haskellNix.sources.nixpkgs-unstable
    haskellNix.nixpkgsArgs;

in pkgs.haskell-nix.project {

  projectFileName = "cabal.project";
  modules = [
    { doCheck = false;
      doCoverage = false;
      doHaddock = false;
      reinstallableLibGhc = true;
      doHoogle = false;
      enableLibraryProfiling = false;
    }

  ];

  src = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "cabal-resolver-issue";
    src = ./.;
  };
  compiler-nix-name = "ghc8107";
}
