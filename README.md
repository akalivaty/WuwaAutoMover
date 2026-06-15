# WuwaAutoMover

WuwaAutoMover is a native macOS GUI app and command line tool for moving Wuthering Waves resource folders to an external disk.

It follows the root README workflow:

- Prepare `/Volumes/<volume>/<external-root>/Resources/<version>`.
- Sync existing local resource folders to the external target.
- Replace both local resource entries with symlinks to the same external target.
- Check current status.
- Remove symlinks without deleting external data.
- Run `codesign` for `WutheringWaves.app` when the game reports a storage or patch-list error.

## Why Swift

This tool is macOS-only and needs native access to AppKit, `.app` bundles, `/Volumes`, `~/Library`, and AppleScript administrator prompts. Swift keeps the GUI, CLI, and macOS integration in one toolchain. Rust would be a good choice for a cross-platform CLI, but it adds more packaging and GUI bridge work for this specific app.

## Build

From the repo root:

```shell
./scripts/build_wuwa_auto_mover.sh
```

Outputs:

- `build/WuwaAutoMover.app`
- `build/wuwa-auto-mover`

Open the GUI:

```shell
open build/WuwaAutoMover.app
```

## CLI

Show help:

```shell
./build/wuwa-auto-mover --help
```

Check status:

```shell
./build/wuwa-auto-mover status --version 3.2.0 --volume T7
```

Create or update symlinks:

```shell
./build/wuwa-auto-mover link --yes --version 3.2.0 --volume T7
```

Remove symlinks without deleting external data:

```shell
./build/wuwa-auto-mover unlink --yes --version 3.2.0 --volume T7
```

Run codesign with a macOS administrator prompt:

```shell
./build/wuwa-auto-mover codesign --admin --app-path "/Volumes/T7/Applications/WutheringWaves.app"
```

`link` and `unlink` require `--yes` because they modify local resource entries. Close Wuthering Waves, Launcher, App Store, and active downloader processes before running them.

## Options

- `--version <value>`: Wuthering Waves resource version. Default: `3.2.0`.
- `--volume <name>`: External volume name under `/Volumes`. Default: `T7`.
- `--external-root <path>`: Folder under the external volume. Default: `WuwaData`.
- `--container-id <id>`: App container ID. Default: `com.kurogame.wutheringwaves.global`.
- `--app-path <path>`: `WutheringWaves.app` path for codesign.
- `--yes`: Required for `link` and `unlink`.
- `--admin`: Use a macOS administrator prompt for `codesign`.

## Homebrew

Templates are under `packaging/homebrew/`:

- `wuwa-auto-mover.rb`: Formula for the CLI.
- `wuwa-auto-mover-cask.rb`: Cask for `WuwaAutoMover.app`, including a `wuwa-auto-mover` binary symlink from the app bundle.

Before publishing, replace `OWNER/REPO` and the placeholder `sha256` values with the real release URL and checksums.
