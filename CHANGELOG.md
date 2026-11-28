# Changelog

All notable changes to **MagicBorder** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Unified Field UI Redesign**: Removed the legacy 3-pane `NavigationSplitView` sidebar and permanent right inspector in favor of a compact, sidebar-free **Field** window (`minWidth: 700, minHeight: 540`) with near-cursor popovers.
- **Interactive Border Seams & Machine Popovers**: Clicking any display tile opens a unified `MachineInspectorPopover` (actions, telemetry, Per-Peer Input Profile, and Per-Device Overlay Override) directly next to the node; clicking any `↔` / `↕` border seam or header pill opens focused rule popovers (`EdgeBehaviorPopover`, `ProtocolAndPairingPopover`, `ClipboardQuickPopover`, `EscapeQuickPopover`).
- **Seamless Tiled List Mode**: Consolidated Grid + Spatial drag-and-drop into `SpatialArrangementView` (`⌘1`) and added `TiledMachineListView` (`⌘2`) with interactive category filter chips (`All`, `Online`, `Windows`, `Mac`, `Saved`, `Nearby`) and one-click connection actions.

### Fixed
- **Disconnected-State Accuracy & Quiet Clipboard Sync**: Prevented clipboard copy events from broadcasting or showing `"Synced clipboard ..."` toasts when no remote machines are connected, silenced routine automatic background copy toasts when connected (reserving toasts for explicit manual push actions), prevented redundant `"Returned to local machine"` and false `"Connection lost"` feedback when idle, gated manual file drop and MWB connect key validation honestly, refined `ToastOverlayView` HUD sizing with deduplication in `MBAppController`, and updated `DashboardView` / `MenuBarView` / machine tiles to reflect disconnected state accurately.

## [0.2.0] - 2026-11-28

### Added
- **End-to-End AES-256-GCM Encryption for Modern (`macOS ↔ macOS`) Mode**: Derives a 256-bit key via `HKDF<SHA256>` from the shared Security Key and seals every JSON frame with `AES.GCM` (rejecting wrong keys, tampering, and plaintext downgrade frames).
- **Per-Peer Input Profiles**: Customize modifier remapping (`⌘ ↔ Ctrl`), scroll inversion, and scroll speed independently per remote machine in `MachineDetailView` (`MBPeerProfileStore`).
- **Live Peer Telemetry & Channel Health**: Reports live Message/Clipboard channel connectivity, heartbeat timestamps, and RTT latency (`ms`) in `MachineDetailView`, `SpatialArrangementView`, and `MenuBarView`.
- **Proportional 2D Spatial Display Canvas**: Toggle between Grid and Spatial monitor views (`SpatialArrangementView`), plus directional crossing arrows, active control badges, right-click actions, and multi-monitor outer-perimeter edge detection.
- **Customizable Global Hotkeys & Lock All Screens**: Interactive hotkey recorder in Input settings (`⌃⌥1–4` machine jump, `⌃⌥L` cursor lock, `⌃⌥P` pause switching, `⌃⌥⌘L` Lock All Screens via `Win+L` + `pmset displaysleepnow`).
- **First-Run Setup Assistant & 3-Stage Connection Doctor**: Guided permissions/pairing wizard, local LAN IP discovery, TCP port probing, saved hosts, and key-redacted diagnostic export.
- **Privacy-Safe Clipboard & Background Lifecycle**: Filters `ConcealedType` / `TransientType` / password-manager entries, enforces max clipboard size limits, promotes `DragDropOverlayView` to a floating `NSPanel`, and adds Launch at Login + Menu Bar Only mode.
- **Redesigned AppIcon & Universal Release Pipeline**: Compiled `AppIcon.icns` / `Assets.car`, localized `InfoPlist.strings`, Universal (`arm64` + `x86_64`) `.dmg` packaging, Homebrew Cask template, parallel CI/CD, and expanded Swift Testing coverage.

### Changed
- Removed unused external `swift-crypto` dependency (zero external SwiftPM dependencies).
- Enabled Swift 6 upcoming features (`ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`) and eliminated all `@unchecked Sendable` conformances and custom `.shared` singletons in `Sources/`.
- Rewrote `README.md` with architecture diagram, pairing guide, quality gates, and build instructions.

### Fixed
- Fixed streaming zlib compression setup in `MWBCompression`, `.hideMouse` cursor handling in `MBNetworkManager`, and `withUnsafeBytes` closure disambiguation across Swift 6.x toolchains.
- Fixed notarization staging (`ditto` zip submission before `stapler`) and `fetch-depth: 0` tag/build-number derivation in `.github/workflows/release.yml`.
