let
  sources = import ./nix/sources.nix {};

  haskellNix = import sources.haskellNix {};
  pkgs = import

    haskellNix.sources.nixpkgs-2111

    haskellNix.nixpkgsArgs;
in pkgs.haskell-nix.project {
  projectFileName = "stack.yaml";
  src = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "cabal-resolver-issue";
    src = ./.;
  };
  compiler-nix-name = "ghc8107";
}
