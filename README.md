# BilouNook

BilouNook is a personal macOS notch utility. It draws a notch-anchored panel
that can open on hover or click, hosts small modules, and shows now-playing
information.

This is a personal project, not a published product. It is accurate to the code
in this repository today.

## Requirements

- macOS 14.6 or later (`MACOSX_DEPLOYMENT_TARGET = 14.6`)
- Xcode (open `BilouNook/BilouNook.xcodeproj`)
- Python 3 for the project and test checks

## Build

From Xcode:

    open BilouNook/BilouNook.xcodeproj
    # then press Cmd-R

From the command line:

    xcodebuild -project BilouNook/BilouNook.xcodeproj -scheme BilouNook \
      -configuration Debug -derivedDataPath ./build build

## Run

The app is a normal macOS application. Build it, then run it from Xcode with
Cmd-R. It has no Dock icon of its own; it lives in the menu bar.

## Test

    xcodebuild -project BilouNook/BilouNook.xcodeproj -scheme BilouNook \
      -configuration Debug -derivedDataPath ./build \
      -destination 'platform=macOS' test

Or run the wrapper that also checks the project file, builds, and tests:

    ./scripts/smoke.sh

`scripts/smoke.sh` writes its logs to `build/logs/`.

## DEBUG launch flags

These flags are DEBUG-only. Each one exits on its own; none leaves the app
running normally.

- `--smoke-test`: opens the notch, closes it, exits 0 on success.
- `--notch-selfcheck`: opens the notch, runs the geometry self-check, prints
  `SELFCHECK PASS` or `SELFCHECK FAIL`, exits 0 or 1.
- `--notch-attach-diag`: prints closed and open attachment snapshots, exits 0.
- `--motion-bench`: runs the motion benchmark.

Example:

    build/Build/Products/Debug/BilouNook.app/Contents/MacOS/BilouNook --smoke-test

## DEBUG hotkeys

Hotkeys are registered in DEBUG builds:

- `Cmd-Option-D`: toggle the debug overlay.
- `Cmd-Option-L`: toggle the Animation Lab.
- `Cmd-Option-J`: play one haptic. If J cannot be registered it falls back to K,
  then U. H is reserved by macOS (`Hide Others`) and is not used.

## Repository layout

    BilouNook/                 Xcode project and app sources
      BilouNook/
        App/                   NSApplicationDelegate and lifecycle
        Window/                Notch panel
        Notch/                 Notch views, shape, geometry, debug overlay
        State/                 Notch state machine
        Interaction/           Mouse, gesture, watchdog, hit regions
        Modules/               Module protocol, registry, Core, Media, A, B
        NowPlaying/            Now-playing providers and service
        Settings/              SettingsStore and settings window
        Haptics/               HapticsService
        Utils/                 Screen resolution
        Debug/                 DEBUG-only diagnostics and hotkeys
        Animations/            Motion constants
      BilouNookTests/          Unit and render tests
    Vendor/MediaRemoteAdapter/ Vendored MediaRemote bridge (see VENDOR.md)
    scripts/                   Project check, build, smoke, icon helpers
    docs/                      Documentation, design specs and media assets

## Demo

[▶ Watch the demo video](docs/media/demo.mp4)

## Install

1. Download the latest `.dmg` file from the [Releases page](https://github.com/bolbol-z/bilOuNook/releases/latest).
2. Open the `.dmg` and drag **BilouNook** into **Applications**.
3. Open it from Launchpad or Spotlight. The app is not signed with a paid Apple Developer ID, so macOS may say it cannot verify the app. Either open **System Settings → Privacy & Security** and click **Open Anyway**, or run this once in Terminal:

```
xattr -dr com.apple.quarantine /Applications/BilouNook.app
```

BilouNook has no Dock icon and no menu-bar item: it lives in the notch. To quit it, use the **Quit BilouNook** item in the notch menu. To uninstall it, quit the app and move it from Applications to the Trash.

Requires macOS 14.6 or later.

## Build from source

Requires macOS 14.6 or later and Xcode.

```
git clone https://github.com/bolbol-z/bilOuNook.git
cd bilOuNook
xcodebuild -project BilouNook/BilouNook.xcodeproj -scheme BilouNook -configuration Release -derivedDataPath build build
open build/Build/Products/Release/BilouNook.app
```

To update an existing clone later:

```
git pull
```

## Limitations

- Now-playing control goes through the vendored `Vendor/MediaRemoteAdapter`, which loads Apple's private MediaRemote framework. The app is therefore not App Store compatible.
