# QuickFLAC

A small, low-RAM FLAC/WAV player for macOS (Swift, SwiftUI, AVAudioEngine). No dependencies.

## Requirements
- macOS 14 or newer
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is NOT required.
  `swift --version` must say 5.9 or newer.
- Note: `@State` is a macro in recent SDKs and its plugin is missing from the Command Line
  Tools, so this project uses its own `@LocalState` (Sources/QuickFLAC/App/LocalState.swift).

## Build and run
Open a terminal **inside this folder** (the one that contains `Package.swift`), then:

    swift run                       # quick start (debug build)
    swift build -c release          # optimized build: use this to measure RAM/launch
    bash Tools/make_app.sh          # builds build/QuickFLAC.app
    open build/QuickFLAC.app

Do NOT run `swift package init` in this folder; the package is already set up.

## Themes
`Sources/QuickFLAC/Resources/themes.json` ships with one theme. To get all Monkeytype themes:

    python3 Tools/convert_themes.py

then rebuild. (Monkeytype is GPL-3.0; this project is for personal use.)

## Measuring
    QUICKFLAC_STATS=1 .build/release/QuickFLAC     # prints launch time
    footprint QuickFLAC                            # RAM, while the app runs

## Layout
    Package.swift
    Tools/                  convert_themes.py, make_app.sh, Info.plist
    Sources/QuickFLAC/
      App/        entry point, playback controller, diagnostics
      Audio/      Player (AVAudioEngine)
      Model/      Track, Library, PlayQueue
      Metadata/   tag reader, artwork
      Themes/     Theme, ThemeStore, Color+Hex
      Views/      library, queue, controls, theme picker
      Resources/  themes.json
