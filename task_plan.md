# Task Plan

## Goal
优化 MagicBorder 的代码结构和功能逻辑，优先解决职责混杂、重复逻辑、状态同步脆弱点，并在不扩大范围的前提下补足基础验证。

## Phases
- [complete] 1. 审查当前结构、找出高价值优化点
- [complete] 2. 与用户确认优化目标和边界
- [complete] 3. 产出优化方案并获得批准
- [complete] 4. 实施首批结构与逻辑重构
- [complete] 5. 运行验证并整理结果

## Constraints
- 尽量保持现有行为不变，避免无关重构
- 优先处理核心路径：输入切换、网络会话、界面状态同步
- 在没有明确需求前，不擅自扩展产品功能

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
