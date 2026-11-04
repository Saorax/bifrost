# bifrost (engine)
a brawlhalla modded client

The new engine Bifrost runs on. Brawlhalla is an Adobe AIR game; this branch converts the game's code, from the
player's own install on their PC, into Haxe and runs it on HashLink + Heaps instead of AIR, with Bifrost's layer from
the `main` branch built in. This repo has no game code, art or files: the conversion happens on each player's PC.

Players get all of this through [the Bifrost app](https://github.com/Saorax/bifrost-app), which downloads the player
kit made here and runs it.

## What's here

| Path | Contents |
| --- | --- |
| `port/runtime/` | the AS3 and Flash runtime the converted game runs on |
| `port/engine-heaps/` | the engine on Heaps: display list, rendering, text and the rest of what AIR provided |
| `port/native/` | C for the engine's native side, so the install's own extensions (sound, Steam) can run |
| `port/tools/steam-launcher/` | the `Brawlhalla.exe` stub Steam's Play starts, which runs Bifrost or Official from the engine folder: `<game>ifrost-engine`, or anywhere else (`tools/port_steam_install.py move`), in which case only the launcher stays in the game folder and carries the engine folder's path |
| `tools/as3_to_haxe.py` | the converter |
| `tools/bifrost_build.py`, `tools/bifrost_export.py` | build Bifrost on the new engine, and export it as a standalone folder |
| `tools/player_kit.py`, `tools/player_engine.py` | build the player kit, and the driver the app runs from it |
| `tools/player_release.py` | make a Bifrost or Official release |
| `tools/setup_*.py` | install the pinned toolchain (Haxe, HashLink, RABCDAsm, OpenFL, the AS3 compiler) |
| `tools/pins.py` | where `main` and bifrost-server are (next to this folder) and which of their commits a release uses (`python tools/pins.py`) |

## Building

You need Python 3.11+, the toolchain (`python tools/setup_haxe.py` and the other `setup_*.py`), Java with FFDec, and
your own Brawlhalla install's files in `versions/<version>/` (git-ignored). Check out `main` next to this folder as
`bifrost`. Then:

```bat
python tools/bifrost_build.py --no-smoke
python tools/player_kit.py build
python tools/player_release.py --product bifrost
```

`player_release.py` prints the `gh release create` command; with `--publish` it creates the release itself.

## Releases

Releases are built on your own PC, because they need your Brawlhalla install and the data the converter made from it,
which never leave it. Both branches have a GitHub Actions workflow (`.github/workflows/release.yml`) that runs on a self-hosted runner there:
every push that changes the source, or a manual run from the Actions tab, builds the release with
`tools/player_release.py --publish` in the engine folder and creates the GitHub release. Players' apps then offer the
update.

One-time setup, in this repo's Settings:

1. **Actions > Runners > New self-hosted runner** (Windows x64): follow its commands in a new folder (for example
   `C:\actions-runner\bifrost`), answer the labels question with `brawlhalla`, and let it run as a service. Python, Git,
   the GitHub CLI and the build toolchain must be on that service's PATH.
2. **Actions > General > Fork pull request workflows**: require approval for all outside collaborators. A public repo's
   pull requests can carry their own workflows, and this runner is your PC, so never approve one you haven't read.
3. Optional **Secrets and variables > Actions > Variables**: `BIFROST_ENGINE_DIR` if the engine branch isn't checked out
   at `C:\Coding\bifrost-engine`, and `BIFROST_SERVER` (`host:port`), the server releases play on (without it, `bifrost.saorax.com:7910`).

The workflow builds from your folders as they are, so push from the same folders you build in.

## License

MIT, see [LICENSE](LICENSE).
