# MagicBorder Feature Acceptance Matrix

五层验收状态定义：

- `Covered`：已有自动化测试或可重复本地验证覆盖。
- `Partial`：核心路径已覆盖，但存在系统权限、UI 或真实设备边界。
- `Manual Required`：必须依赖 macOS 权限、局域网、Windows/MWB 或真实输入设备验证。
- `Missing`：当前实现或验证缺失，不能声明功能完成。

## Matrix

| Feature | State | Effect | Protocol | Remote | Recovery | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 权限与输入捕获 | Partial | Partial | Covered | Manual Required | Partial | `MBInputManager` 协议转换已测试；真实 event tap、Accessibility 授权和本地放行策略需手动验证。 |
| 设备发现 | Partial | Partial | Partial | Manual Required | Partial | UI 可显示 discovery state；Bonjour/subnet 扫描需真实同网段验证。 |
| MWB 配对 | Covered | Partial | Covered | Manual Required | Covered | host/port/key 参数、日志与错误路径已自动化；Windows MWB 兼容仍需手动。 |
| 现代传输 | Partial | Partial | Partial | Manual Required | Partial | 连接事件和输入 packet 入口可测试；文件/矩阵在 `MBModernTransport` 仍为空实现，不标记完成。 |
| 机器布局 | Covered | Covered | Covered | Manual Required | Covered | `MachineArrangement`、`MachineListResolver`、`syncArrangement` 覆盖排序、stale slot、矩阵名称同步。 |
| 边缘切换 | Covered | Covered | Partial | Manual Required | Covered | 手动切换、本机回退、MWB/modern 状态切换和断线恢复已覆盖；真实屏幕边缘手感需实机。 |
| 输入转发 | Covered | Partial | Covered | Manual Required | Partial | mouse/key/scroll 事件转换已覆盖；真实 CGEvent 注入/Windows 端响应需手动。 |
| 剪贴板 | Covered | Partial | Covered | Manual Required | Covered | 本地开关、远端 incoming text/image/files、ignore-next-change、overlay 清理已有测试或实现入口；跨设备粘贴需手动。 |
| 文件拖放 | Covered | Covered | Covered | Manual Required | Covered | `transferFiles` gating、fake transport 发送和远端 incoming gating 已覆盖；真实 Windows drop 需手动。 |
| 设置 | Covered | Covered | Covered | Manual Required | Covered | 注入式 `UserDefaults`、端口范围、key 校验、持久化恢复和 apply transport 已覆盖。 |
| 菜单栏 | Partial | Partial | Partial | Manual Required | Partial | 菜单项连接真实 network/settings 入口；缺少自动 UI 验证，需手动。 |
| 诊断反馈 | Covered | Covered | Covered | Manual Required | Covered | pairing log/error、toast 入口和错误配置恢复已覆盖；日志复制和实机排障需手动。 |

## Current Automated Coverage

- `CompatibilitySettingsTests`：默认值、端口范围、持久化隔离、安全 key 校验。
- `NetworkManagerTests`：fake transport 事件、断线回本机、settings apply、文件传输开关、矩阵同步、诊断日志、手动 host 连接。
- `SessionCoordinatorTests`：modern/MWB 手动切换、本机回退、未知目标保护、相对鼠标模式不居中、transport active nil 恢复。
- `InputManagerTests`：mouse/key/scroll/flagsChanged 到 modern `RemoteEvent` 的协议转换，以及常用 Mac 到 Windows key mapping。
- `MachineArrangementTests` / `MachineListResolverTests`：矩阵导航、环绕、增删移动、stale slot、本机兜底和重复 ID 防护。
- `ClipboardBridgeTests` / `MWBTransportTests`：剪贴板/文件开关 gating 和 MWB host 字符串转换。

## Known Gaps

- `MBModernTransport.sendFileDrop` 和 modern matrix 远端行为仍是空实现或不完整实现，只能标 `Partial`。
- 真实输入捕获依赖 macOS Accessibility/TCC 和 CGEvent tap，自动化不能替代实机验收。
- Windows MWB 的协议兼容性、端口防火墙、安全 key 错误提示必须在 Windows 主机上验证。
- 菜单栏、拖放 overlay、系统设置跳转缺少自动 UI 测试，本轮只保证它们连接到真实业务入口。
