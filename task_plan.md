# Task Plan

## Goal
在 `main` 上完成全功能五层验收与自动化优先的缺陷补全：建立验收矩阵、手动端到端清单、测试支撑层，并补齐可自动证明的核心功能正确性测试与修复。

## Phases
- [complete] 1. 审查当前结构、找出高价值优化点
- [complete] 2. 与用户确认优化目标和边界
- [complete] 3. 产出优化方案并获得批准
- [complete] 4. 实施首批结构与逻辑重构
- [complete] 5. 运行验证并整理结果
- [complete] 6. 建立五层验收矩阵和手动 E2E 清单
- [complete] 7. 建立 fake transport / test settings 支撑层
- [complete] 8. 补齐核心功能自动化验收测试与修复
- [complete] 9. 运行格式、测试、构建验证
- [in_progress] 10. 直接提交并推送 main

## Constraints
- 尽量保持现有行为不变，避免无关重构
- 优先处理核心路径：输入切换、网络会话、界面状态同步
- 在没有明确需求前，不擅自扩展产品功能
- 用户已明确要求直接在 `main` 实施、提交并推送
- 自动化优先；真实 Windows/MWB 端到端行为写入手动验收清单

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| `securityKey` 初始化触发 transport 配置时崩溃 | 新增 `NetworkManagerTests` 后运行 `swift test` | 增加 `currentTransportIfAvailable`，初始化期安全跳过，装配后显式配置 |
| 持久化端口 `0` 被接受 | 新增端口范围测试 | `MBCompatibilitySettings.portValue` 改为只接受 `1...65535` |
