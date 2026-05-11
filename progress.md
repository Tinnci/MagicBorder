# Progress

## 2026-05-11

- 读取并应用 `planning-with-files` 技能。
- 读取并应用 `brainstorming` 技能的前置流程约束。
- 完成首轮仓库勘察：README、Package、入口、Dashboard、NetworkManager、InputManager、SessionCoordinator、PairingFlow、CLI。
- 建立任务文件：`task_plan.md`、`findings.md`、`progress.md`。
- 用户确认“两者一起做，但先抓最影响稳定性的部分”。
- 创建实施计划：`docs/superpowers/plans/2026-05-11-stability-refactor.md`。
- 添加 SwiftPM 测试目标 `MagicBorderKitTests`。
- 添加 `MachineArrangementTests`，覆盖无效列数、单行环绕、不完整网格环绕。
- 添加 `MachineListResolverTests`，覆盖本机兜底、布局排序、陈旧 slot、重复 ID、本机 ID 被错误连接项覆盖。
- 新增 `MachineListResolver`，把 UI 可见机器排序从 `DashboardView` 下沉到 `MagicBorderKit`。
- `MBNetworkManager` 新增 `visibleMachines()` 和 `syncArrangement(machineIDs:twoRow:swap:)`，收口布局同步入口。
- `DashboardView` 改为通过 `networkManager.visibleMachines()` 刷新列表，并通过 `syncArrangement` 同步布局。
- `MachineArrangement.next` 对无效列数做 `max(1, columns)` 防护，避免除零风险。
- 验证：`swift test` 通过 7 个测试；`swift build` 通过。
- 提交上一阶段改动：`1d4bdec refactor: stabilize machine arrangement state`，提交钩子 SwiftFormat 和 SwiftLint 均通过。
- 完成 UI/功能实现审查并按严重性记录 10 个问题。
- 修复设置窗口不会即时应用安全密钥/端口的问题。
- 修复 Wrap Mouse 设置未接入 `MBCompatibilitySettings.wrapCursor` 的问题。
- 修正网络端口默认值显示为 MWB 实际默认端口 `15101/15100`。
- 配对前会 trim IP 并应用最新兼容设置。
- 重写机器详情页，移除未实现的固定应用、显示设置、输入设置和假刷新。
- 机器矩阵拖拽改为 drop 时一次性重排，避免 hover 期间反复同步矩阵。
- 验证：`swiftformat --lint` 针对改动 UI 文件通过；`swift test` 通过 7 个测试；`swift build` 通过。
