# Contributing to Tiley

Thanks for contributing.

## Prerequisites

- macOS 14.6 or later
- Xcode (latest stable recommended)
- Swift 5.9+

## Build and Test

From repository root:

```bash
swift build
swift test
```

Run locally:

```bash
swift run
```

On first launch, grant Accessibility permission in System Settings so the app can control other windows.

You can also open [Tiley.xcodeproj](./Tiley.xcodeproj) and run with Xcode:

- Open [Tiley.xcodeproj](./Tiley.xcodeproj) in Xcode
- Select the `Tiley` scheme
- Build or run as a standard macOS app target

## Project Layout

```
Sources/Tiley/
├── App/             # App entry point, lifecycle, central state
├── Models/          # Grid selection, layout presets, hotkey models
├── Services/        # Accessibility API, window management
└── UI/
    ├── MainWindow/  # Settings window
    └── Layout/      # Layout preset editor, grid preview
```

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

## Development Notes

- Keep changes focused and small.
- Prefer clear, explicit code over clever shortcuts.
- Preserve existing behavior unless the PR intentionally changes it.
- Update docs when behavior or release steps change.

## Pull Requests

- Include a short problem statement and solution summary.
- Mention user-visible behavior changes.
- List verification steps (commands run and manual checks).
- If relevant, include screenshots or short clips for UI changes.

## Commit Style

- Use concise, imperative commit messages.
- Example: `Fix hover selection priority for layout presets`

## License

By contributing, you agree that your contributions are licensed under the Apache License 2.0.
