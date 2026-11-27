# Changelog

All notable changes to **MagicBorder** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Redesigned macOS `AppIcon` asset catalog across all 10 standard icon slots and wired `actool` compilation (`AppIcon.icns` + `Assets.car`) into `.app` release packaging.
- Universal (`arm64` + `x86_64`) release packaging, drag-to-Applications `.dmg` layout, `MagicBorder.entitlements`, localized `InfoPlist.strings` (`en`, `zh-Hans`), and Homebrew Cask template (`Packaging/homebrew/magicborder.rb`).
- Parallelized GitHub Actions CI (`static-checks`, `quality-and-coverage`, `tsan-and-package`) with `llvm-cov` step summaries, Dependabot updates, and release gating with SLSA build provenance attestation.
- Repository governance and developer tooling: `Makefile`, `scripts/check_static.sh`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, GitHub issue/PR templates, and `.swift-format`.
- Segregated transport protocols, `MBSessionCoordinator`, `MBClipboardBridge`, `MBDiscoveryService`, `MBConnectionRegistry`, `MWBStreamFramer`, `MWBSessionChannel`, `MWBHandshakeStateMachine`, `MWBReconnectPolicy`, and `SystemAbstractions` test seams.
- Expanded Swift Testing suite (`Testing`) covering protocol framing, compression, crypto, key mapping, edge transitions, clipboard bridging, pasteboard monitoring, and live loopback transports.

### Changed
- Removed unused external `swift-crypto` dependency (zero external SwiftPM dependencies).
- Enabled Swift 6 upcoming features (`ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`) and eliminated all `@unchecked Sendable` conformances and custom `.shared` singletons in `Sources/`.
- Rewrote `README.md` with architecture diagram, pairing guide, quality gates, and build instructions.

### Fixed
- Fixed streaming zlib compression setup in `MWBCompression`, `.hideMouse` cursor handling in `MBNetworkManager`, and `withUnsafeBytes` closure disambiguation across Swift 6.x toolchains.
- Fixed notarization staging (`ditto` zip submission before `stapler`) and `fetch-depth: 0` tag/build-number derivation in `.github/workflows/release.yml`.
