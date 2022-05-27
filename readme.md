[![Build status](https://github.com/peterbecich/cabal-resolver-issue/actions/workflows/ci.yml/badge.svg)](https://github.com/peterbecich/cabal-resolver-issue/actions/workflows/ci.yml)

[![Build status](https://github.com/peterbecich/cabal-resolver-issue/actions/workflows/nix-cabal.yml/badge.svg)](https://github.com/peterbecich/cabal-resolver-issue/actions/workflows/nix-cabal.yml)

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

## Workflow

In https://github.com/haskell/cabal,

```
cabal install cabal-install --overwrite-policy=always
```

The bug is reproduced by switching between `enable-tests` and `disable-tests`.
In this repo, try

```
time ~/.cabal/bin/cabal build all --disable-tests --dry-run > disabled.log
```
and
```
time ~/.cabal/bin/cabal build all --enable-tests --dry-run > enabled.log
```
, then `diff disabled.log enabled.log`.

Also, try `--verbose:`
```
time ~/.cabal/bin/cabal build all --disable-tests --dry-run --verbose > disabled.log
time ~/.cabal/bin/cabal build all --enable-tests --dry-run --verbose > enabled.log
```

Print statements placed here
https://github.com/haskell/cabal/blob/ec3cf26ae6021b7ca9f496a39efbcba50e459015/cabal-install/src/Distribution/Client/ProjectPlanning.hs#L413-L416
indicate that the `improved-plan`
https://github.com/haskell/cabal/blob/ec3cf26ae6021b7ca9f496a39efbcba50e459015/doc/nix-local-build.rst#caching
changes, triggering the 30~40 second resolver.

### My results using Cabal 3.4

From disabled tests to enabled tests
```
cabal build all --disable-tests --dry-run > disabled.log
1.50s user 0.15s system 99% cpu 1.655 total

cabal build all --enable-tests --dry-run > enabled.log 
30.89s user 0.79s system 99% cpu 31.790 total
```
See `disabled_to_enabled.diff`.

From enabled tests to disabled tests
```
cabal build all --enable-tests --dry-run > enabled.log  
1.90s user 0.20s system 100% cpu 2.108 total

cabal build all --disable-tests --dry-run > disabled.log  
29.72s user 0.85s system 99% cpu 30.668 total
```
See `enabled_to_disabled.diff`.

The message "cannot read state cache" is of interest. The message is defined here:
https://github.com/haskell/cabal/blob/ec3cf26ae6021b7ca9f496a39efbcba50e459015/cabal-install/src/Distribution/Client/ProjectOrchestration.hs#L954-L955
