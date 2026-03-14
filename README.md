# Tiley

**[https://yusuke.github.io/tiley/](https://yusuke.github.io/tiley/)**

Tiley is a macOS menu bar utility written in Swift that recreates the core Tiley workflow:

- Shows a grid overlay for the active display
- Lets you drag across cells to define a target region
- Moves and resizes the frontmost window through the macOS Accessibility API
- Includes direct menu presets for halves, corners, and maximize
- Supports Apple Silicon through a native Swift/macOS build
- Provides a global shortcut: `Shift + Command + Space`

## Project layout

```
Sources/Tiley/
├── App/             # App entry point, lifecycle, central state
├── Models/          # Grid selection, layout presets, hotkey models
├── Services/        # Accessibility API, window management
└── UI/
    ├── MainWindow/  # Settings window
    └── Layout/      # Layout preset editor, grid preview
```

## Run

```bash
swift run
```

On first launch, grant Accessibility permission in System Settings so the app can control other windows.

## Open In Xcode

- Open [Tiley.xcodeproj](./Tiley.xcodeproj) in Xcode
- Select the `Tiley` scheme
- Build or run as a standard macOS app target

You can still use the Swift Package workflow if preferred.

## Developer ID Release

For direct distribution outside the Mac App Store, archive, notarize, and staple with:

```bash
KEYCHAIN_PROFILE=AC_NOTARY scripts/release_notarize.sh
```

Or with an App Store Connect API key:

```bash
API_KEY_PATH=~/keys/AuthKey_ABC123XYZ.p8 \
API_KEY_ID=ABC123XYZ \
API_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
scripts/release_notarize.sh
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](./LICENSE).
