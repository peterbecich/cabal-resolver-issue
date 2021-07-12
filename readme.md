Attempt to replicate issue https://github.com/haskell/cabal/issues/7466.

This is a Cabal project with an intricate dependency tree, but no source code. It was obfuscated using `obfuscate.hs`.

Run `cabal clean` followed by `cabal build all --dry-run`. The latter takes about 40 seconds locally to run, but is
faster on subsequent runs. Switching between `--enable-tests` and `--disable-test` incurs this 40-second cost again.

## `cabal configure`

```
% cabal clean
% cabal update
% time cabal configure
Resolving dependencies...
Build profile: -w ghc-8.10.4 -O1
...
cabal configure  43.40s user 9.81s system 52% cpu 1:42.08 total
% time cabal configure
'cabal.project.local' already exists, backing it up to 'cabal.project.local~'.
Build profile: -w ghc-8.10.4 -O1
...
cabal configure  7.67s user 2.02s system 54% cpu 17.941 total
```

## `cabal build all --dry-run`

```
% cabal clean
% cabal update
% time cabal build all --dry-run
Resolving dependencies...
Build profile: -w ghc-8.10.4 -O1
...
cabal build all --dry-run  44.71s user 9.52s system 45% cpu 1:59.77 total
% time cabal build all --dry-run
Build profile: -w ghc-8.10.4 -O1
...
cabal build all --dry-run  8.51s user 2.14s system 56% cpu 18.757 total
```

## Other considerations

- Deleting `cabal.project.freeze` and compare with that
- Use the `master` branch of the Cabal project

## Package versions

- Cabal 3.4.0.0 (via ghcup)
- GHC 8.10.4 (via ghcup)
