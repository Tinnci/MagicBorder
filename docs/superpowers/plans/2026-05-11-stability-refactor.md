# Stability Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the most stability-sensitive structure and logic around machine arrangement and UI-visible machine ordering.

**Architecture:** Keep network transport behavior unchanged. Move pure ordering/navigation rules into `MagicBorderKit/Domain` where they can be tested, then simplify SwiftUI state synchronization to call those rules through `MBNetworkManager`.

**Tech Stack:** Swift 6.1, Swift Package Manager, XCTest, SwiftUI, MagicBorderKit.

---

### Task 1: Harden Arrangement Navigation

**Files:**
- Modify: `Sources/MagicBorderKit/Domain/MachineArrangement.swift`
- Test: `Tests/MagicBorderKitTests/MachineArrangementTests.swift`

- [x] Add tests for zero-column fallback and incomplete wrapped grids.
- [x] Run the tests and confirm the new tests fail on current code.
- [x] Normalize column count inside `MachineArrangement.next`.
- [x] Re-run targeted tests.

### Task 2: Extract Visible Machine Ordering

**Files:**
- Create: `Sources/MagicBorderKit/Domain/MachineListResolver.swift`
- Modify: `Sources/MagicBorderKit/Network/NetworkManager.swift`
- Modify: `Sources/MagicBorder/UI/DashboardView.swift`
- Test: `Tests/MagicBorderKitTests/MachineListResolverTests.swift`

- [x] Add tests for local-first fallback, arrangement ordering, stale slot filtering, and connected-machine append behavior.
- [x] Run the tests and confirm the resolver does not exist yet.
- [x] Implement `MachineListResolver`.
- [x] Expose `MBNetworkManager.visibleMachines()` and use it from `DashboardView`.
- [x] Re-run targeted tests.

### Task 3: Collapse Duplicate Matrix Sync Logic

**Files:**
- Modify: `Sources/MagicBorderKit/Network/NetworkManager.swift`
- Modify: `Sources/MagicBorder/UI/DashboardView.swift`

- [x] Add one `syncArrangement(machineIDs:)` API that updates local arrangement and sends the matrix once.
- [x] Update `ArrangementDetailView` to call that API from machine reorder/settings changes.
- [x] Run `swift test` and `swift build`.
