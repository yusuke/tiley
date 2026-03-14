# Contributing to Tiley

Thanks for contributing.

## Prerequisites

- macOS 13 or later
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

You can also open [Tiley.xcodeproj](./Tiley.xcodeproj) and run with Xcode.

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
