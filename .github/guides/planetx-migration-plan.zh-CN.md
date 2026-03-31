****# Planet X 迁移执行手册（并入 BoardGames Lobby）

本手册用于将 `ref/planetx_server` + `ref/planetx_client` 逐步吸收进当前仓库架构（`boardgames_server` + `bg_runtime` + `lib`）。

目标：在不破坏现有 Acquire 的前提下，使 Planet X 以“第二款游戏”方式接入当前统一大厅、房间与协议体系。

最后更新：2026-03-31

---

## 0. 迁移范围与原则

### 0.1 迁移范围

- 迁移：Planet X 的规则引擎、状态机、操作校验、推荐逻辑。
- 不直接迁移：旧项目的 Socket 事件命名和 GetX 全局架构。
- 改造接入：统一走当前项目的 `RoomManager + action/broadcast/message` 协议。

### 0.2 核心原则

1. 先后端、后前端（先跑通最小闭环，再完善 UI/交互）。
2. 先兼容现有协议，再谈“协议美化”。
3. 全过程保持 Acquire 可用，不做破坏式重构。

---

## 1. 现状对照

### 1.1 当前项目接入点（必须遵守）

- 服务端游戏抽象：`boardgames_server/src/game.rs`
- 房间与游戏注册：`boardgames_server/src/room.rs`
- Socket 协议入口：`boardgames_server/src/server.rs`
- 运行时注册游戏：`bg_runtime/src/main.rs`
- Flutter 游戏路由：`lib/src/room/room_game_router.dart`
- Flutter 统一网络层：`lib/src/api/lobby_api.dart`

### 1.2 参考项目主要资产（可复用）

- 规则/状态：`ref/planetx_server/src/map`, `ref/planetx_server/src/operation`, `ref/planetx_server/src/recommendation`, `ref/planetx_server/src/room/game_state.rs`
- 客户端 UI 组件：`ref/planetx_client/lib/component`, `ref/planetx_client/lib/pages/game.dart`
- 客户端模型：`ref/planetx_client/lib/model`

---

## 2. 里程碑总览（按顺序执行）

| 里程碑 | 目标 | 预计耗时 | 验收结果 |
|---|---|---:|---|
| M1 | PlanetX 插件壳接入 Rust workspace | 0.5 天 | `list_games` 可见 `planetx` |
| M2 | 迁移规则内核（无前端） | 1.5~2 天 | `cargo test -p planetx_plugin` 通过 |
| M3 | 统一协议适配（action/broadcast/message） | 1~1.5 天 | 可创建房间并完成至少 1 轮操作 |
| M4 | Flutter 最小房间页接入 | 1 天 | 可进入 `planetx` 房间并展示状态 |
| M5 | PlanetX 交互页迁移与联调 | 1.5~2 天 | 核心流程可玩，断线重连可恢复 |
| M6 | 回归与文档收尾 | 0.5~1 天 | Acquire 无回归，文档同步完成 |

---

## 3. 分阶段执行步骤

## 3.1 M1: 创建 PlanetX 插件骨架并注册

### 操作

1. 新建 Rust crate：`planetx_plugin`（结构可参考 `acquire_plugin`）。
2. 在根 `Cargo.toml` 的 `workspace.members` 增加 `planetx_plugin`。
3. 在 `bg_runtime/src/main.rs` 注册 PlanetX 游戏实例到 `RoomManager`。
4. 确定 game_id：固定为 `planetx`。

### 命令

```bash
cargo check --workspace
```

### 验收

- 服务启动后，前端调用 `list_games` 返回中包含：`acquire`, `planetx`。

### 勾选

- [x] `planetx_plugin` crate 创建
- [x] workspace 注册完成
- [x] runtime 注册完成
- [ ] `list_games` 可见 `planetx`

---

## 3.2 M2: 迁移 PlanetX 规则内核（纯后端逻辑）

### 操作

1. 从 `ref/planetx_server` 迁移以下模块到 `planetx_plugin`：
   - `map/`
   - `operation/`
   - `recommendation/`
   - 状态核心（可拆成 `state/`）
2. 清理旧通信耦合：去掉对 `socketioxide::SocketRef` 等直接依赖。
3. 将错误类型统一映射到 `boardgames_server::game::GameError`。
4. 在 `planetx_plugin` 补齐单元测试（至少覆盖开局、回合推进、关键操作、推荐）。

### 命令

```bash
cargo test -p planetx_plugin
```

### 验收

- PlanetX 规则在无网络环境下可测试。
- 关键规则与旧项目行为一致（操作合法性、状态推进、推荐结果格式）。

### 勾选

- [x] 规则模块迁移完成（map/operation/recommendation + model 已迁入）
- [x] 通信层耦合清理完成（旧 socket 依赖未引入插件）
- [x] 测试通过（`cargo test -p planetx_plugin`，8 passed）

---

## 3.3 M3: 适配当前统一协议

### 操作

1. 在 `planetx_plugin` 实现 `Game` trait：
   - `descriptor`
   - `create_initial_state`
   - `handle_action`
   - `on_join` / `on_start`（按需）
2. 设计 action payload 兼容层：
   - 将旧 `room/op/recommend/sync` 语义统一封装到 `action.payload.type`。
3. 输出统一消息：
   - 房间级状态更新通过 `broadcast(type=state)`
   - 操作反馈通过 `message`
4. 明确幂等字段：复用现有 `Action.id`。

### 建议 payload 结构

```json
{
  "type": "planetx_op",
  "op": {
    "kind": "research",
    "...": "..."
  }
}
```

可额外约定：`planetx_room_op`, `planetx_recommend`, `planetx_sync`。

### 命令

```bash
cargo check --workspace
```

### 验收

- 大厅可创建 `planetx` 房间。
- 两名玩家 ready 后可开局。
- 至少一轮操作可完成并广播状态。

### 勾选

- [ ] `Game` trait 实现完成
- [ ] action payload 协议落地
- [ ] 状态广播与消息反馈可用

---

## 3.4 M4: Flutter 最小接入（先展示后交互）

### 操作

1. 新建目录：
   - `lib/src/games/planetx/data`
   - `lib/src/games/planetx/presentation`
2. 参考 `AcquireClient` 新建 `PlanetXClient`，统一使用 `LobbyApi.sendAction`。
3. 在 `room_game_router.dart` 增加 `case 'planetx'`。
4. 先实现只读房间页：
   - 展示房间状态
   - 展示最近广播
   - 操作按钮可留最小集（如 sync/research 示例）

### 命令

```bash
flutter analyze
```

### 验收

- 可进入 PlanetX 房间页面。
- 可看到服务端广播状态。
- 可发送至少一个 action 并看到反馈。

### 勾选

- [ ] 前端目录与客户端封装完成
- [ ] 路由接入完成
- [ ] 最小页面可用

---

## 3.5 M5: PlanetX 页面迁移与交互完善

### 操作

1. 从 `ref/planetx_client` 迁移 UI 组件（星图、操作栏、日志等）。
2. 去 GetX 化：
   - 状态由页面局部状态 + `LobbyApi` 监听承接。
3. 保留现有项目风格：
   - 遵守当前 i18n 方案（`lib/src/i18n`）
   - 不引入第二套全局路由/依赖注入体系
4. 增强断线重连与重进房间恢复。

### 命令

```bash
flutter analyze
```

### 验收

- PlanetX 核心对局流程可跑通。
- 断线重连后可恢复到当前房间状态。
- Acquire 页面与流程无回归。

### 勾选

- [ ] 关键组件迁移完成
- [ ] 交互闭环完成
- [ ] 重连恢复可用

---

## 3.6 M6: 回归与收尾

### 操作

1. 后端回归：双游戏房间并发创建与操作。
2. 前端回归：大厅、房间、离开重进、异常提示。
3. 文档补充：协议字段、页面说明、已知限制。

### 命令

```bash
cargo check --workspace
flutter analyze
```

### 验收

- 双游戏（Acquire/PlanetX）均可用。
- CI 基础检查通过。

### 勾选

- [ ] 双游戏回归完成
- [ ] 文档更新完成
- [ ] 可发布状态确认

---

## 4. 迁移风险与对应策略

1. 协议不兼容风险（最高）
- 风险：旧 `planetx_server` 使用 `room/op/recommend/sync` 事件，当前是统一 `action`。
- 策略：仅迁移领域逻辑，协议层重写为适配层。

2. 客户端架构冲突风险
- 风险：旧客户端是 GetX 全家桶，当前项目未采用。
- 策略：保留 UI 组件，重写状态管理与事件订阅。

3. 回归风险（影响 Acquire）
- 风险：共享房间与服务器逻辑修改可能影响已有流程。
- 策略：每个里程碑都执行双游戏 smoke test。

---

## 5. 建议提交节奏（可直接照抄）

1. `feat(server): register planetx game skeleton in runtime`
2. `feat(planetx): migrate core rules and state model`
3. `feat(planetx): adapt action payload to unified room protocol`
4. `feat(client): add planetx room route and minimal page`
5. `feat(client): port planetx interactive widgets`
6. `chore(doc): finalize planetx migration notes and checklists`

---

## 6. 开工前检查清单

- [ ] 当前分支可编译（`cargo check --workspace` + `flutter analyze`）
- [ ] Acquire 当前流程可手工走通
- [ ] 明确 `planetx` game_id 不变
- [ ] 明确第一阶段只做后端，不做 UI 重构

---

## 7. 完成定义（Definition of Done）

满足以下全部条件即视为迁移完成：

1. 大厅可创建并进入 PlanetX 房间。
2. PlanetX 完成至少一局最小流程（开局 -> 多轮操作 -> 结束）。
3. 断线重连后可恢复状态。
4. Acquire 无功能回归。
5. 文档与协议说明已更新到 `.github/guides`。

---

## 8. M1 执行清单（可直接照做）

本节用于第一阶段落地：只完成 PlanetX 插件壳接入与运行时注册，不迁移具体规则。

### 8.1 目标

- 服务端能注册并识别 `planetx` 游戏。
- 大厅 `list_games` 可返回 `planetx`。
- 不要求此阶段可完整开局。

### 8.2 文件改动清单

1. 根工作区
- `Cargo.toml`
   - 在 `workspace.members` 追加 `planetx_plugin`。

2. 新建插件目录
- `planetx_plugin/Cargo.toml`
   - 声明 crate 名称、edition、依赖（建议与 `acquire_plugin` 同级最小依赖）。
- `planetx_plugin/src/lib.rs`
   - 提供 `PlanetXGame` 结构体。
   - 实现最小 `Game` trait（descriptor + create_initial_state + handle_action）。
- `planetx_plugin/src/model.rs`
   - 提供最小状态结构并实现 `GameState`（snapshot/restore 可先用 JSON）。

3. 运行时注册
- `bg_runtime/src/main.rs`
   - 引入 `planetx_plugin::PlanetXGame`。
   - 在 `RoomManager` 注册 `planetx`。

### 8.3 建议提交顺序

1. 提交 A：`chore(rust): add planetx_plugin crate skeleton`
   - 新建 `planetx_plugin` 目录与最小代码。

2. 提交 B：`chore(workspace): include planetx_plugin member`
   - 修改根 `Cargo.toml`。

3. 提交 C：`feat(runtime): register planetx game in bg_runtime`
   - 修改 `bg_runtime/src/main.rs`。

### 8.4 每步验收命令

```bash
cargo check --workspace
```

通过后启动服务端，再做最小联调：

```bash
cargo run -p bg_runtime
```

前端进入大厅后检查游戏列表是否出现 `planetx`。

### 8.5 M1 完成判定

- [x] `cargo check --workspace` 通过
- [ ] 服务可启动
- [ ] `list_games` 返回包含 `planetx`
- [ ] Acquire 仍可创建房间（无回归）

### 8.6 M1 常见问题

1. 编译报 trait 未实现
- 检查 `PlanetXGame` 是否完整实现了 `Game` trait 所需方法。

2. `list_games` 没有 planetx
- 检查 `bg_runtime/src/main.rs` 是否调用 `rm.register_game(...)`。
- 检查 `descriptor().id` 是否为 `planetx`。

3. 启动后创建房间失败
- 检查创建房间时传入 game_id 是否为 `planetx`（区分大小写）。

---

## 9. M2 文件级迁移映射（ref -> planetx_plugin）

本节用于第二阶段：将旧服务端领域逻辑迁移到新插件，同时避免把旧 socket 绑定代码带入。

## 9.1 建议目标目录

建议在 `planetx_plugin/src` 使用如下结构：

- `lib.rs`
- `model.rs`
- `engine.rs`
- `map/`
- `operation/`
- `recommendation/`
- `tests.rs`

## 9.2 映射总表

| 参考文件 | 目标文件 | 处理方式 | 说明 |
|---|---|---|---|
| `ref/planetx_server/src/map/*` | `planetx_plugin/src/map/*` | 直接迁移为主 | 纯规则层，可复用率高 |
| `ref/planetx_server/src/operation/*` | `planetx_plugin/src/operation/*` | 迁移后改错误类型 | 统一映射到 `GameError` |
| `ref/planetx_server/src/recommendation/*` | `planetx_plugin/src/recommendation/*` | 直接迁移为主 | 与 socket 解耦后可复用 |
| `ref/planetx_server/src/room/game_state.rs` | `planetx_plugin/src/model.rs` | 结构重组 | 保留状态字段，移除网络相关字段 |
| `ref/planetx_server/src/server_state.rs` | 不迁移 | 重写/删除 | 这是旧服务器全局状态，不属于插件 |
| `ref/planetx_server/src/server_handler.rs` | 不迁移 | 重写为 `engine.rs` 内 action 分发 | 旧事件处理需改为统一 `handle_action` |
| `ref/planetx_server/src/main.rs` | 不迁移 | 删除 | 启动入口由 `bg_runtime` 统一管理 |
| `ref/planetx_server/src/room/server_resp.rs` | `planetx_plugin/src/engine.rs` 内 message payload | 语义迁移 | 转成统一 message/broadcast 格式 |

## 9.3 重点改造点

1. 事件改造
- 旧：`socket.emit("game_state")`, `socket.emit("op_result")`。
- 新：返回 `ActionResult::Ok { events, broadcasts }`，由框架发送。

2. 鉴权与用户查找
- 旧：在 `server_state` 里通过 socket_id 查 user。
- 新：直接使用 `Action.user_id`，插件不感知 socket。

3. 房间操作语义
- 旧：`room` 事件承载 create/join/leave/prepare。
- 新：房间管理由上层统一处理，插件只处理“游戏内动作”。

4. 错误与提示
- 旧：`ServerResp::RoomErrors/OpErrors/...`。
- 新：`GameError::Invalid/State/Internal/Retryable` + message payload。

## 9.4 M2 建议任务拆分

1. 任务 1：迁移 map + operation + recommendation
- 验收：模块可编译，基础测试可运行。

2. 任务 2：重建 PlanetXState
- 验收：`snapshot/restore` 可往返，字段完整。

3. 任务 3：编写 engine 的 action 分发
- 验收：至少支持一条核心 op（如 research）闭环。

4. 任务 4：补齐最小测试矩阵
- 验收：开局、回合推进、非法操作、推荐逻辑均有测试。

## 9.5 M2 完成判定

- [x] 旧服务端规则层已迁移到 `planetx_plugin`（首批：map/operation/recommendation/model）
- [x] 旧 socket 绑定代码未被引入插件
- [x] `cargo test -p planetx_plugin` 通过
- [x] 可进入 M3 协议适配阶段

---

## 10. M3 协议字段对照表（旧事件 -> 新统一协议）

本表用于实现 `planetx_plugin::handle_action` 时统一 payload 语义。

## 10.1 客户端请求映射

| 旧请求事件 | 旧负载 | 新请求入口 | 新 payload 建议 |
|---|---|---|---|
| `op` | `Operation` | `action` | `{ "type": "planetx_op", "op": { ... } }` |
| `recommend` | `RecommendOperation` | `action` | `{ "type": "planetx_recommend", "op": { ... } }` |
| `sync` | 空 | `action` | `{ "type": "planetx_sync" }` |
| `room`（旧游戏内控制） | `RoomUserOperation` | 不进入插件 | 由现有房间 API 负责（create/join/leave/set_ready） |

## 10.2 服务端响应映射

| 旧服务端事件 | 新建议通道 | 新 payload 建议 |
|---|---|---|
| `game_state` | `broadcast` | `{ "type": "state", "game": "planetx", "state": { ... } }` |
| `op_result` | `message`（给操作者） | `{ "type": "planetx_op_result", "result": { ... } }` |
| `recommend_result` | `message`（给操作者） | `{ "type": "planetx_recommend_result", "result": { ... } }` |
| `game_start` | `broadcast` | `{ "type": "planetx_game_start", "state": { ... } }` |
| `xclue` | `message`（定向） | `{ "type": "planetx_xclue", "items": [ ... ] }` |
| `token` | `message`（定向） | `{ "type": "planetx_token", "tokens": [ ... ] }` |
| `board_tokens` | `broadcast` | `{ "type": "planetx_board_tokens", "tokens": [ ... ] }` |
| `server_resp.*` | `message` 或 action error | 可落在 `GameError` 或 `{ "type": "planetx_error", "code": "..." }` |

## 10.3 action payload 最小规范

建议统一字段：

```json
{
   "type": "planetx_op",
   "op": {
      "kind": "survey",
      "params": {
         "sector_type": "comet",
         "range": [1, 6]
      }
   }
}
```

要求：

1. `type` 必填，用于路由分发。
2. `op.kind` 必填，用于具体规则逻辑。
3. 参数校验失败必须返回可读错误码（建议 snake_case）。

## 10.4 错误码建议

| 错误码 | 含义 |
|---|---|
| `planetx_invalid_payload` | payload 结构非法 |
| `planetx_unknown_action_type` | 不支持的 type |
| `planetx_invalid_op` | 不合法操作 |
| `planetx_not_current_player` | 非当前玩家操作 |
| `planetx_invalid_stage` | 当前阶段不允许该操作 |
| `planetx_state_conflict` | 状态冲突或并发冲突 |

## 10.5 M3 完成判定

- [ ] 客户端可通过统一 `action` 发送 PlanetX 操作
- [ ] 插件可返回规范化 `broadcast/message`
- [ ] 至少 1 条核心操作链路跑通（请求 -> 状态更新 -> 反馈）
- [ ] 错误码与提示语义可稳定复现
