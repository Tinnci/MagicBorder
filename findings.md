# Findings

## 2026-05-11

- 项目是 Swift Package，包含 `MagicBorder` GUI、`MagicBorderKit` 核心库、`MagicBorderCLI` 命令行入口。
- 最近几次提交已经在做架构收口：transport adapter、session coordinator、clipboard bridge 已被逐步从 `NetworkManager` 中抽离。
- 当前没有 `Tests/` 目录，说明结构优化后需要至少补一层可自动验证的测试或最低限度的编译验证。
- 入口对象主要通过 SwiftUI environment 注入：`MBAccessibilityService`、`MBInputManager.shared`、`MBNetworkManager.shared`、`MBOverlayPreferencesStore`。
- `MBNetworkManager` 仍然承担较多职责：发现、连接、toast、配对日志、会话切换委托、剪贴板桥接、布局同步、文件选择。
- `DashboardView` 承担了一部分状态拼装职责，例如机器列表排序、本机机器注入、overlay 偏好回退逻辑。
- `MBSessionCoordinator` 已经是核心切换状态机，适合继续承接与“激活机器/边缘切换/状态同步”相关的纯逻辑。

## UI and Function Implementation Review

Ranked by severity:

1. Settings changes for security key and ports were not guaranteed to reconfigure the active transport when changed from the Settings window.
2. `Wrap Mouse at Screen Edge` was stored in a standalone `@AppStorage("wrapMouse")` key and did not control `MBCompatibilitySettings.wrapCursor`, so the UI toggle did not affect input routing.
3. Network settings showed defaults `20000/20001`, while the transport defaults and pairing guide use `15101/15100`.
4. Pairing used the raw IP text and did not apply the latest compatibility settings immediately before connecting.
5. `MachineDetailView` exposed placeholder app launching and display/input settings that were not backed by app functionality.
6. Machine matrix drag reordering synchronized layout repeatedly while hovering across cards instead of once on drop.
7. Machine detail refresh used a timer animation without refreshing any real state.
8. Several visible status labels in machine cards/details were hard-coded or under-localized.
9. `DispatchQueue.main.asyncAfter` is used for transient UI messages and can update view state after the originating view is no longer relevant.
10. Some SwiftUI APIs still use older styling patterns such as `cornerRadius`, and a few icon-only buttons rely on help text rather than explicit labels.
