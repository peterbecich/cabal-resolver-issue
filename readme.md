
Attempt to replicate issue https://github.com/haskell/cabal/issues/7466.

This is a Cabal project with 400 packages. Each package has 40 random dependencies drawn from `dependencies.txt`, plus `base`. The items in `dependencies.txt` are taken from https://hackage.haskell.org/packages/browse.

Run `cabal configure`. For me, `cabal configure` runs noticeably faster on the second run:

```
% cabal clean 

% time cabal configure   
Resolving dependencies...
Build profile: -w ghc-8.10.4 -O1
...
cabal configure  12.40s user 0.46s system 99% cpu 12.889 total

% time cabal configure 
'cabal.project.local' already exists, backing it up to 'cabal.project.local~'.
Build profile: -w ghc-8.10.4 -O1
...
cabal configure  4.70s user 0.38s system 98% cpu 5.135 total
```

Run `cabal build all --dry-run`:

```
% cabal clean
% time cabal build all --dry-run 
Resolving dependencies...
Build profile: -w ghc-8.10.4 -O1
...
cabal build all --dry-run  12.52s user 0.32s system 99% cpu 12.857 total

% time cabal build all --dry-run 
Build profile: -w ghc-8.10.4 -O1
...
cabal build all --dry-run  0.89s user 0.10s system 99% cpu 0.995 total
```

Also, I suggest deleting `cabal.project.freeze` and comparing with that.

To generate new packages:
- inspect `generate.sh`
- `rm -rf package*`
- `./generate.sh`

I'm using:
- Debian 10.10
- Cabal 3.4.0.0 (via ghcup)
- GHC 8.10.4 (via ghcup)
