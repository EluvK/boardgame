# Planet X 迁移执行手册（并入 BoardGames Lobby）

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

当前已实现（2026-03-31）：

- `planetx_sync`：返回当前状态快照。
- `planetx_op`：已接入真实计算首版（`survey` / `target` / `research` / `locate`）。
- `planetx_recommend`：已接入真实计算（基于 `ChoiceFilter` 返回 `count` / `can_locate`）。

### 勾选

- [x] `Game` trait 实现完成
- [x] action payload 协议落地（最小支持 `planetx_op`/`planetx_recommend`/`planetx_sync`）
- [x] 状态广播与消息反馈可用（MVP）

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

- [x] 前端目录与客户端封装完成
- [x] 路由接入完成
- [x] 最小页面可用

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

- [x] 关键组件迁移完成（首批：状态面板 + 星区渲染 + 操作日志 + 基础操作栏）
- [x] 页面结构已与旧 `game.dart` 同构（RoomInfos/MessageBar/GameResult/OpBar + StarMap/Logs）
- [x] 组件拆分首轮完成（`planetx_sections.dart` + `planetx_star_map.dart` + `planetx_op_bar.dart` + `planetx_logs.dart`）
- [x] 交互闭环完成（已覆盖：sync/recommend/survey/target/research/locate/ready_publish/do_publish）
- [x] 重连恢复可用（页面重进可恢复标记与关键视图状态）

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

## 6. 当前阶段检查清单（M6）

- [ ] 基础检查通过：`cargo check --workspace` + `flutter analyze`
- [ ] PlanetX 插件测试通过：`cargo test -p planetx_plugin`
- [ ] Acquire 手工 smoke 完成（建房、ready、开局、操作）
- [ ] PlanetX 手工 smoke 完成（含 survey/target/research/locate/publish）
- [ ] 双房并发验证完成（Acquire 与 PlanetX 同时在线）

---

## 7. 完成定义（Definition of Done）

满足以下全部条件即视为迁移完成：

1. 大厅可创建并进入 PlanetX 房间。
2. PlanetX 完成至少一局最小流程（开局 -> 多轮操作 -> 结束）。
3. 断线重连后可恢复状态。
4. Acquire 无功能回归。
5. 文档与协议说明已更新到 `.github/guides`。

---

## 8. 当前状态快照（精简）

### 8.1 已完成（不再展开历史细节）

- M1~M5 主体已完成。
- 已具备：插件接入、规则迁移、统一协议、前端路由与页面、核心交互闭环。
- 已覆盖操作：`sync / recommend / survey / target / research / locate / ready_publish / do_publish`。
- 已完成首版恢复：页面重进后可恢复关键 UI 状态（标记与视图开关）。

### 8.2 仍未完成（需继续执行）

- [x] 日志面板结构化展示（已支持字段化展示与 raw 展开）。
- [ ] M6 双游戏回归（Acquire + PlanetX 并发 smoke test）。
- [ ] 文档收尾：补充前端 payload 示例与错误处理示例。

---

## 9. 后续执行步骤（按优先级）

### Step 1: 日志结构化增强（中优先级）

目标：把 `OpLog / ClueLog / MeetingLog` 从纯文本改为字段化展示，保留原始文本兜底。

执行项：

1. 在前端定义日志行模型（时间、操作者、操作类型、摘要、原始 payload）。
2. 在消息监听处按 `planetx_op_result / planetx_recommend_result / state.event` 解析并入库。
3. 更新日志组件为表格列展示（类型、操作者、摘要、时间），点击可展开 raw。

验收：

- `flutter analyze` 无告警。
- UI 可清晰区分三类日志，且可查看原始 JSON。

### Step 2: M6 双游戏回归（高优先级发布前门槛）

目标：确认 PlanetX 增量没有影响 Acquire，且双游戏并存稳定。

执行项：

1. 启动服务后验证 `list_games` 同时包含 `acquire` 与 `planetx`。
2. Acquire smoke：建房、ready、开局、至少 1 次操作。
3. PlanetX smoke：建房、ready、开局、执行 `survey/target/research/locate/publish` 至少各 1 次。
4. 并发验证：两个房间同时在线，互不串房/串消息。

验收：

- `cargo check --workspace` 通过。
- `cargo test -p planetx_plugin` 通过。
- `flutter analyze` 通过。
- 两游戏流程均可手工走通。

当前进度（2026-03-31）：

- [x] `cargo check --workspace` 已执行通过（仅现存 warning）。
- [x] `cargo test -p planetx_plugin` 已执行通过（8 passed）。
- [x] `flutter analyze lib test` 已执行（存在 1 条历史 info，非本次变更引入）。
- [ ] Acquire 手工 smoke 待执行。
- [ ] PlanetX 手工 smoke 待执行。
- [ ] 双房并发手工验证待执行。

### Step 3: 文档收尾（低优先级）

目标：让迁移文档可直接用于后续维护与排障。

执行项：

1. 在本手册增加“前端 action payload 示例”小节（至少 4 个：survey/locate/ready_publish/do_publish）。
2. 增加“常见错误码 -> 前端提示语”对照表。
3. 将本节执行结果回填到 M6 勾选状态。

---

## 10. 本轮完成定义（收口标准）

满足以下全部条件后，将 M6 三项全部勾选：

1. 双游戏回归完成。
2. 文档示例与错误处理说明补齐。
3. 可发布状态确认（无阻断问题）。
