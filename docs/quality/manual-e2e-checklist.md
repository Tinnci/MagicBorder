# MagicBorder Manual E2E Checklist

本清单覆盖自动化无法可靠证明的系统权限、真实局域网、Windows/MWB 和输入设备行为。失败时先查看 App 内 Pairing Debug Log；需要更细日志时用 `MAGICBORDER_DEBUG=1` 启动，并同时查看 macOS Console 中 `MagicBorder` 相关日志。

## Preconditions

- 两台机器在同一局域网，macOS 端运行 MagicBorder。
- macOS `System Settings > Privacy & Security > Accessibility` 已允许 MagicBorder。
- Windows 端安装并运行 MWB 兼容服务，防火墙允许 message port `15101` 和 clipboard port `15100`，除非本轮故意测试错误端口。
- 两端使用相同 security key，长度至少 16 位。

## Checks

| Area | Steps | Expected Result | Failure Signals |
| --- | --- | --- | --- |
| macOS 权限 | 关闭 Accessibility 权限后启动 App，再打开 Settings 权限提示。点击 `Open System Settings` 并授权。 | App 不崩溃；授权后可启用 `Capture Local Input`。 | 无法打开系统设置；event tap 创建失败日志持续出现。 |
| 同网段发现 | 两端接入同一网段，打开 Dashboard/Pairing。等待 Bonjour/subnet 扫描。 | 远端设备出现在 discovered 或可连接列表。 | discovered 为空；Console 中 Bonjour 或 subnet scan 报错。 |
| Windows MWB 配对 | 输入正确 Windows IP 和默认端口，使用相同 security key 点击 Connect。 | Pairing Debug Log 出现连接/握手日志；远端机器进入 connected。 | `pairingError` 显示 key、端口或连接错误。 |
| 手动 IP 连接 | 在 Pairing flow 输入带空格的 IP，例如 ` 192.168.1.10 ` 后连接。 | IP 被 trim；transport 使用正确 host 和 port。 | 日志中 host 带空格；连接未发起。 |
| 鼠标移动 | 切换到 Windows 机器后移动鼠标。分别测试 absolute 和 relative 模式。 | Windows 光标跟随移动；relative 模式无明显跳变。 | 光标不动、方向反向、移动比例异常。 |
| 点击 | 在远端机器上执行左键、右键按下和抬起。 | Windows 收到对应点击，未发生重复点击。 | 点击丢失或 down/up 粘连。 |
| 滚轮 | 在远端窗口内上下滚动。 | Windows 窗口按正确方向滚动。 | 方向反、滚动量过大或无响应。 |
| 键盘 | 输入普通字母、数字、回车、空格、Esc。 | 远端应用收到正确按键；Esc 可触发回本机路径。 | key mapping 错误；Esc 无法恢复。 |
| 修饰键 | 测试 Shift、Control、Option/Alt、Command/Windows 组合键。 | 组合键在 Windows 上按预期触发。 | flagsChanged 粘键、组合键丢失。 |
| 剪贴板文本 | 启用 `Share Clipboard`，在 macOS 复制文本后到 Windows 粘贴；再反向复制。 | 两端文本一致；本机不会重复触发同一变更。 | 文本不同步、重复 toast、粘贴旧内容。 |
| 剪贴板图片 | 启用 `Share Clipboard`，复制图片并在远端粘贴。 | 图片可在远端应用粘贴。 | 图片为空、格式不支持、日志有 clipboard error。 |
| 文件拖放 | 启用 `Transfer Files`，从 Dashboard 或拖放入口发送文件/文件夹。 | Windows 收到文件；overlay 状态从 dragging/dropping 回到空。 | 开关关闭仍发送；overlay 不清理；文件路径丢失。 |
| 断线恢复 | 切到远端后断开 Windows 服务或拔网，等待 disconnect。 | active machine 自动回本机；toast/日志提示断开。 | 输入仍被拦截；activeMachineId 未清空。 |
| 端口错误 | 设置错误 message port 后连接。 | 连接失败但 App 不崩溃；日志显示端口或连接错误。 | 无限等待且无日志；设置无法恢复。 |
| 安全 key 错误 | 两端配置不同 security key 后连接。 | 连接失败并在 Pairing Debug Log/Error 中提示认证或 key 问题。 | 错误 key 仍能连接；没有任何反馈。 |
| 菜单栏 | 从菜单栏打开窗口、切换机器、本机回退、切换剪贴板/文件/边缘开关。 | 所有菜单项连接真实状态；开关与 Settings/Dashboard 保持一致。 | 菜单项看似可用但状态不变。 |

## Exit Criteria

- 所有 `Expected Result` 满足，或失败项有日志、截图和复现步骤。
- 自动化测试 `swift test` 通过。
- `feature-acceptance.md` 中仍为 `Manual Required` 的项已在本清单中执行并记录结果。
