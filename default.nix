{ #compiler ? "ghc8107",
  # ghcjsVersion ? "8.8.4",
  #ghcVersion ? "8.10.7",
  withCoverage ? false,
  doCheck ? false,
  doCoverage ? false,
  doHaddock ? false,
}:
  let
    sources = import ./nix/sources.nix {};

    haskellNix = import sources.haskellNix {};
    pkgs = import

      haskellNix.sources.nixpkgs-2105

      haskellNix.nixpkgsArgs;
  in pkgs.haskell-nix.project {
    src = pkgs.haskell-nix.haskellLib.cleanGit {
      name = "cabal-resolver-issue";
      src = ./.;
      # exactDeps = true;
    };
    compiler-nix-name = "ghc8107";
  }
