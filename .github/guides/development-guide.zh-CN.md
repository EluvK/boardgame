# Boardgame 项目开发指南

本指南面向本仓库的日常开发，目标是让新任务可以按统一路径推进：
- 明确模块边界（Rust 服务端 / Flutter 客户端 / 游戏插件）
- 保持多游戏扩展能力（Acquire + PlanetX）
- 减少跨层耦合与回归风险

## 1. 项目目标与技术栈

- 目标：构建通用桌游联机平台，承载多款游戏逻辑插件。
- 服务端：Rust（workspace 多 crate）+ Socket.IO + Salvo。
- 客户端：Flutter（Web/桌面优先），通过 Socket.IO 与服务端通信。

## 2. 仓库结构与职责

### 2.1 Rust workspace（服务端）

- `boardgames_server/`
  - 通用房间、玩家、事件分发与游戏抽象接口。
  - 关键模块：`src/game.rs`（抽象协议）、`src/room.rs`（房间管理）、`src/server.rs`（Socket.IO 事件入口）。
- `acquire_plugin/`
  - Acquire 规则引擎与状态推进。
- `planetx_plugin/`
  - PlanetX 规则、地图、操作、推荐逻辑。
- `bg_runtime/`
  - 服务端可执行入口，负责注册插件并启动服务。

### 2.2 Flutter（客户端）

- `lib/main.dart`
  - 应用启动、本地存储初始化、国际化初始化。
- `lib/src/api/`
  - 网络与大厅 API（连接、房间基础动作、通用 action 发送）。
- `lib/src/room/`
  - 房间公共壳层：会话模型、gameId 路由、未接入游戏兜底页。
- `lib/src/games/acquire/`
  - Acquire 专属模型与页面。
- `lib/src/games/planetx/`
  - PlanetX 专属模型与页面。
- `lib/src/models/`
  - 过渡/共享模型导出（兼容历史引用）。
- `lib/src/utils/`
  - 设备身份、偏好存储、本地持久化辅助。

## 3. 关键边界约束（开发必须遵守）

1. `src/room` 只做公共房间壳与分发，不承载具体游戏规则与页面业务。
2. 各游戏实现只放在 `src/games/<gameId>/`，跨游戏复用能力需明确抽象后再上提。
3. 服务端状态快照是前端真值来源，客户端不做规则推演。
4. `lobby_api.dart` 保持传输层职责，不写具体游戏动作语义。
5. 插件 crate 只实现本游戏规则，不反向依赖客户端结构。

## 4. 本地开发与验证流程

### 4.1 启动服务端

```bash
cargo run -p bg_runtime
```

默认地址：`http://127.0.0.1:17980`，Socket 路径：`/socket.io`。

### 4.2 启动客户端（Web）

```bash
flutter run -d chrome
```

### 4.3 基础检查（提交前最少执行）

```bash
cargo check --workspace
flutter analyze
```

若改动了核心规则或协议，建议补充：

```bash
cargo test --workspace
flutter test
```

## 5. 新增游戏的标准接入步骤

1. 服务端新增插件 crate 或在现有插件中补齐 `Game` 实现。
2. 在 `bg_runtime/src/main.rs` 注册新游戏插件。
3. 客户端新增 `lib/src/games/<new_game_id>/`，完成 data + presentation。
4. 在 `lib/src/room/room_game_router.dart` 中新增 `gameId` 分发 case。
5. 通过大厅创建房间并做端到端联调（建房、入房、动作、广播、离房）。

## 6. 常见改动场景建议

- 改协议字段：先更新服务端协议输出，再同步客户端模型解析，最后补回归校验。
- 改 UI 交互：优先在对应游戏目录内完成，避免把游戏逻辑塞进公共 room 层。
- 改房间流程：优先修改 `boardgames_server/src/room.rs` 与客户端 `src/room/` 壳层，不直接散落到游戏页面。

## 7. 文档维护约定

1. 长期规范更新到本指南或对应“持续维护”文档。
2. 带日期的阶段总结放入历史归档，不作为当前唯一事实来源。
3. 同主题冲突时，以“持续维护”文档为准，并在变更 PR 里说明差异来源。

## 8. 建议阅读顺序

1. `README.md`
2. `.github/index.md`
3. `.github/guides/development-guide.zh-CN.md`
4. `.github/guides/acquire-client-architecture.zh-CN.md`
5. `.github/guides/acquire-client-server-protocol.zh-CN.md`