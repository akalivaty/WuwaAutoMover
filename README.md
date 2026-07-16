# WuwaAutoMover

WuwaAutoMover is a native macOS GUI app for moving Wuthering Waves resource data to an external disk.

You can refer to this [repo](https://github.com/akalivaty/move_wuwa_to_extenal_disk_on_mac) and this tool will practice this process automatically.

It supports the three workflows described in the root README:

1. **Recommended**: codesign the App Store app first, then link only `~/Library/Client/Saved/Resources/<version>`.
2. **Second choice**: link the whole `~/Library/Client` folder to the external disk.
3. **Conservative fallback**: link both the sandbox container resource path and the `~/Library/Client` resource path.

Settings are saved after you enter them, so you do not need to retype your paths every time.

## Install

Download the latest DMG from GitHub Releases, open it, and drag `WuwaAutoMover.app` to the Applications shortcut.

WuwaAutoMover is ad-hoc signed and is not notarized because this project does not use an Apple Developer membership. On first launch, macOS may require opening the app from Finder with Control-click, `Open`, then confirming again.

### Build From Source

From `WuwaAutoMover/`:

```shell
swift build -c release
```

To package the app and a downloadable DMG:

```shell
./scripts/build_wuwa_auto_mover.sh
./scripts/create_dmg.sh
```

The build script copies the release executable into the app bundle, verifies its signature, and then removes `.build/release` and its underlying SwiftPM release directory. The DMG script reads only `build/WuwaAutoMover.app`, so it can run immediately afterward without the Swift build artifacts.

Outputs:

- `build/WuwaAutoMover.app`
- `build/WuwaAutoMover-<version>.dmg`

Open the GUI:

```shell
open build/WuwaAutoMover.app
```

The DMG script uses `ditto` to preserve the complete app bundle, then adds an `/Applications` symlink and installation notes. Builds are ad-hoc signed.

## GUI Usage

Fill in your own values. The text shown in the fields is only a placeholder example, not a default.

On the first launch, choose English or Traditional Chinese. WuwaAutoMover saves this preference and uses it on future launches.

Required settings:

- Resource version, for example `3.4.0`
- External destination folder under `/Volumes`, for example `/Volumes/T7/WuwaData`. The GUI obtains the volume name from this path automatically.
- App container ID, for example `com.kurogame.wutheringwaves.global`
- Absolute path to `WutheringWaves.app`, for example `/Volumes/T7/Applications/WutheringWaves.app`

Follow the guided order in the GUI:

1. Enter the resource version and select the external destination folder and game app. Selected paths are written into the text fields and saved automatically.
2. Click `Check Now` / `開始檢查`. This is the first action to run each time the app starts. If either local `Resources` folder contains visible entries other than the current version, the app lists them and asks whether to delete all of them, including `Video`. For stale symlinks, the linked data under the configured external `Resources` folder is deleted too.
3. Close Wuthering Waves, Launcher, App Store, and downloader processes, tick the confirmation checkbox, then run workflow A.

Codesigning the game app can take several minutes. While it runs, the GUI shows an activity indicator and a message asking you to keep WuwaAutoMover open.

Press `Command-Q` or click the window's red close button to quit WuwaAutoMover. If an operation is still running, the app asks for confirmation before quitting.

Workflow B and C are fallbacks for cases where workflow A does not work. Workflow buttons remain clickable and show the missing prerequisite when status check or shutdown confirmation has not been completed.

## Automatic Updates

WuwaAutoMover embeds Sparkle 2 and uses signed GitHub Release assets:

- The app checks for updates automatically once per day.
- Automatic download and installation are enabled by default.
- Use `WuwaAutoMover` > `Check for Updates...` / `檢查更新...` to check manually.
- Update archives and the appcast are verified with the project's Sparkle EdDSA key.
- If a file operation is running when Sparkle requests a relaunch, WuwaAutoMover's existing quit confirmation prevents an accidental interruption.

The fixed update feed is:

```text
https://github.com/akalivaty/WuwaAutoMover/releases/latest/download/appcast.xml
```

The Sparkle private key is stored in the local macOS Keychain under account `dev.yuva.WuwaAutoMover`. Never commit or upload the private key as a repository file. Because there is no Developer ID fallback, losing both the Keychain key and the GitHub secret prevents existing installations from trusting future updates.

## Release Automation

This repository includes a GitHub Actions workflow at:

```text
.github/workflows/release.yml
```

Before the first release, export the existing private key to a temporary file:

```shell
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account dev.yuva.WuwaAutoMover \
  -x /tmp/WuwaAutoMover-sparkle-private-key
```

In GitHub, open `Settings` > `Secrets and variables` > `Actions`, create the repository secret `SPARKLE_PRIVATE_KEY`, and use the complete temporary file contents as its value. Delete the temporary file immediately afterward:

```shell
rm -f /tmp/WuwaAutoMover-sparkle-private-key
```

The release flow is:

1. Commit and push your WuwaAutoMover changes.
2. Create and push a version tag, for example `v1.0.0`.
3. GitHub Actions builds `WuwaAutoMover.app` on `macos-latest`.
4. The workflow packages `WuwaAutoMover.app` as `WuwaAutoMover-<version>.dmg`.
5. Sparkle signs the DMG and `appcast.xml` with `SPARKLE_PRIVATE_KEY`.
6. The workflow creates or updates the GitHub Release and uploads both files.

Create a release:

```shell
git tag v1.0.0
git push origin v1.0.0
```

The tag name must start with `v`; for example, `v1.0.0` produces `WuwaAutoMover-1.0.0.dmg`. Each release also receives a monotonically increasing `CFBundleVersion` from `github.run_number`, which Sparkle uses for update comparison.
