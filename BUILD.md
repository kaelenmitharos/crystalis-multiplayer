# Build Instructions

You need Node.js and npm on your path, GNU Make, and a POSIX shell
(on Windows, Git Bash works).

The build itself also needs your Crystalis ROM (see below): copy it into the
repo root before running `make`, because the build tools search the current
folder for it.

```
npm install        # get packages
make debug         # builds target/debug/bin/cryr (the command-line randomizer)
```

`make release` builds a minified copy under `target/release`, and
`make web-debug` builds the web version.

## Building a ROM

The build reads data from your own Crystalis ROM. Use the US release whose
SHA-1 is `fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64`. Never commit a ROM;
`*.nes` is already in `.gitignore`.

```
mkdir -p out
node target/debug/bin/cryr --flags="Dn Vmsw" --seed=0 --output=out/%s_%c Crystalis.nes
```

`Dn Vmsw` keeps items, maps, shops and wild warp in their original places,
which is handy for testing. Add `Cp` to turn on the co-op work in progress.

## Windows notes

- Install GNU Make, for example with `winget install ezwinports.make`, and
  run the commands above from Git Bash.
- `.gitattributes` forces LF line endings. If you cloned before it existed
  and the build fails on CRLF, run
  `git config core.autocrlf false`, then `git rm --cached -r . && git reset --hard`
  to check the files out again (this discards uncommitted changes).
