# Boardgame 仓库级 Copilot 约束

本文件定义本仓库的固定协作约束，适用于所有新会话。

## 1. 总体目标

- 维持“通用大厅 + 游戏插件”架构，不把单游戏逻辑扩散到公共层。
- 优先保证协议兼容、状态一致性和多人联机稳定性。

## 2. 目录与职责边界

1. `boardgames_server/` 负责通用房间、玩家、事件分发、Game 抽象。
2. `acquire_plugin/` 与 `planetx_plugin/` 仅负责各自规则与状态推进。
3. `bg_runtime/` 仅负责注册游戏与启动服务，不承载规则实现。
4. `lib/src/room/` 只做房间公共壳和 gameId 分发，不写具体游戏业务。
5. 游戏客户端逻辑必须放在 `lib/src/games/<gameId>/`。
6. `lib/src/api/lobby_api.dart` 保持传输层职责，不写具体游戏规则语义。

## 3. 开发行为约束

1. 默认做最小改动，不做与任务无关的重构或重排。
2. 不修改 `build/`、`target/`、`logs/` 这类产物目录内容。
3. 不删除或覆盖历史归档文档中的内容，除非任务明确要求。
4. 涉及协议字段或事件名改动时，必须同步检查客户端模型解析与路由分发。
5. 涉及 UI 改动时，不得把游戏特有逻辑回灌到 `src/room` 公共层。

## 4. 状态与协议原则

1. 服务端广播 state 快照为前端真值，前端不做规则推演。
2. action 失败路径要保留可见错误信息，不静默吞错。
3. `room_game_router.dart` 中 `gameId` 映射必须与服务端注册 ID 一致。

## 5. 质量门禁（提交前）

至少执行：

```bash
cargo check --workspace
flutter analyze
```

如果改动规则、协议或关键交互，补充执行：

```bash
cargo test --workspace
flutter test
```

## 6. 文档同步要求

1. 长期规范变更同步更新 `.github/guides/development-guide.zh-CN.md`。
2. 文档索引变更同步更新 `.github/index.md`。