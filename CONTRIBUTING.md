# Contributing to MagicBorder

Thank you for contributing to MagicBorder!

## Prerequisites

- **macOS 14.0+** (Apple Silicon or Intel)
- **Xcode 16+ / Swift 6.1+** (Swift 6 language mode with upcoming features enabled)
- Optional: [SwiftLint](https://github.com/realm/SwiftLint) and [`pre-commit`](https://pre-commit.com/)

MagicBorder has **zero external SwiftPM dependencies**, so cloning and building works offline in seconds.

## Quick Development Workflow

```bash
git clone https://github.com/Tinnci/MagicBorder.git
cd MagicBorder

# Run all local CI gates (static checks, swift format lint, strict debug build, unit tests, TSan)
make check
```

Useful `Makefile` targets:

| Target | Command | Purpose |
| --- | --- | --- |
| `make format` | `swift format format --in-place --recursive Sources Tests` | Format Swift sources and tests |
| `make format-lint` | `swift format lint --strict --recursive Sources Tests` | Verify formatting matches `.swift-format` |
| `make static-check` | `bash scripts/check_static.sh` | Verify localization parity, plists, and Swift 6 guardrails |
| `make build` | `swift build -Xswiftc -warnings-as-errors` | Debug build with warnings treated as errors |
| `make test` | `swift test` | Run the Swift Testing suite |
| `make tsan` | `swift test --sanitize=thread` | Run tests under Thread Sanitizer |
| `make coverage` | `swift test --enable-code-coverage` | Print `llvm-cov` coverage report for `MagicBorderKit` |
| `make package` | `ARCH_MODE=universal CREATE_DMG=1 bash scripts/release_package.sh` | Build Universal `.app` and `.dmg` in `dist/` |

## Engineering Standards

1. **Swift 6 Concurrency & Language Features**: `ExistentialAny`, `InternalImportsByDefault`, and `MemberImportVisibility` are enabled package-wide. Do **not** add `@unchecked Sendable` or custom `.shared` singletons in `Sources/`.
2. **Protocol-Oriented Abstractions**: Keep domain/protocol logic in `MagicBorderKit` pure and testable. Depend on injected protocols (`ClockProviding`, `ScreenGeometryProviding`, `CursorControlling`, `PasteboardAccessing`, `ScreenCapturing`, `MBTransport`) rather than calling AppKit/CoreGraphics globals directly inside business logic.
3. **Zero Warnings**: All code and tests must compile cleanly under `-Xswiftc -warnings-as-errors` and pass `swift format lint --strict`.
4. **Localization Parity**: User-facing strings live in both `Sources/MagicBorder/Resources/en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings` (and plist descriptions in `InfoPlist.strings`). Always update both locales together; `make static-check` enforces key parity.
5. **Testing**: Add Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) coverage for bug fixes and new behaviors, and verify `make tsan` stays race-free.

## Pull Request Process

1. Create a focused branch from `main`.
2. Run `make check` locally and verify zero errors or warnings.
3. Fill out the Pull Request template checklist honestly and clearly.
