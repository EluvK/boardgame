# PlanetX 现状对比说明（current vs ref）

最后更新：2026-04-02

本文档用于对齐当前仓库中的 PlanetX 实现与 `ref/planetx_server`、`ref/planetx_client` 的差距，作为后续迭代执行依据。

## 1. 结论摘要

1. 当前 PlanetX 已完成“可接入统一大厅 + 可在房间内进行核心操作”的基础闭环。
2. 服务端已迁移为插件模式（`planetx_plugin`），并接入统一房间框架（`boardgames_server`）。
3. 客户端已完成独立页面与核心组件重建（星图、操作栏、日志）。
4. 当前最大差距不是“是否可玩”，而是“与 ref 状态机和事件语义是否完全一致”。
5. 最关键规则差距：当前 `PlanetXStage` 没有 `MeetingCheck` 阶段，而 ref 有。
6. 协议层已从 ref 的专有事件（`room/op/recommend/sync`）迁移为统一 `action + broadcast/message`，这属于架构差异，不是简单 bug。
7. PlanetX 目前建议定位为“迁移中版本（可联调）”，不建议按“已完全对齐 ref”对外宣称完成。

## 2. 对比范围

- 当前服务端：`planetx_plugin` + `boardgames_server` + `bg_runtime`
- 当前客户端：`lib/src/games/planetx`
- 参考服务端：`ref/planetx_server`
- 参考客户端：`ref/planetx_client`

## 3. 服务端对比（逐项）

### 3.1 架构层

- ref：独立 socket 服务，核心在 `ref/planetx_server/src/server_handler.rs`。
- current：插件化接入，核心在 `planetx_plugin/src/lib.rs`，由 `bg_runtime/src/main.rs` 注册。
- 判定：这是预期架构升级，不属于缺陷。

### 3.2 状态机阶段

- ref：`UserMove -> MeetingProposal -> MeetingPublish -> MeetingCheck -> LastMove -> GameEnd`（见 `ref/planetx_server/src/room/game_state.rs`）。
- current：`UserMove -> MeetingProposal -> MeetingPublish -> LastMove -> GameEnd`（见 `planetx_plugin/src/model.rs` 中 `PlanetXStage`）。
- 差距：缺少 `MeetingCheck`，会导致阶段语义与 ref 不完全一致。
- 优先级：P0。

### 3.3 会议结算流程

- current 在 `planetx_plugin/src/lib.rs` 的 `MeetingPublish` 分支里直接调用 `resolve_meeting_checks` 后切回 `UserMove`。
- ref 将会议检查显式建模为 `MeetingCheck` 阶段（阶段更清晰，便于客户端展示与调试）。
- 差距：逻辑能力部分存在，但阶段建模不一致。
- 优先级：P0。

### 3.4 玩家位置与回合语义

- ref 使用 `UserLocationSequence(index/round/child_index)`（见 `ref/planetx_server/src/room/game_state.rs`）。
- current 使用 `player_steps` + `turn_index`（见 `planetx_plugin/src/model.rs`）。
- 差距：表达方式不同，跨圈与相对顺序推导路径不同，需要更多对照测试保证等价。
- 优先级：P1。

### 3.5 操作模型与推荐

- 操作枚举与结果模型总体兼容：`survey/target/research/locate/ready_publish/do_publish`。
- 推荐能力（count/can_locate）已在 current 保留（`planetx_plugin/src/lib.rs`）。
- 判定：能力级别基本对齐，主要风险在阶段与时机，而非操作类型本身。

## 4. 客户端对比（逐项）

### 4.1 页面与组件结构

- ref：`pages/game.dart` + `component/*` + GetX 控制器。
- current：`planetx_room_page.dart` + `components/planetx_*` + `PlanetXClient`。
- 判定：结构已完成迁移，且已去除对旧 GetX 全局模式的依赖。

### 4.2 阶段驱动操作栏

- current 的 `planetx_op_bar.dart` 已按阶段限制操作（`user_move`、`meeting_proposal`、`meeting_publish`、`last_move`、`game_end`）。
- 因服务端缺 `meeting_check`，客户端也未建对应分支。
- 差距：阶段展示与 ref 不完全一致。
- 优先级：P1（依赖服务端 P0 修复）。

### 4.3 协议接收模型

- current 通过 `PlanetXStateEnvelope` + `LobbyApi` 处理统一 `broadcast/message`。
- ref 客户端直接处理专有事件（`game_state/game_start/op_result/token/board_tokens/xclue`）。
- 判定：这是架构改造结果，current 方向正确，但需要补齐文档与测试来证明行为等价。

## 5. 协议与事件语义差异

### 5.1 ref 协议形态

- 连接命名空间：`/xplanet`
- 主事件：`room`、`op`、`recommend`、`sync`
- 推送：`game_state`、`op_result`、`game_start`、`token`、`board_tokens`、`xclue`

### 5.2 current 协议形态

- 统一命名空间与房间框架：由 `boardgames_server` 接管
- 上行：`action`（PlanetX 动作封装为 `planetx_op/planetx_sync/planetx_recommend`）
- 下行：`action_result` + `broadcast/message`（`type: state` 及 `planetx_*_result`）

### 5.3 当前问题定位

- 问题不在“是否用了旧事件名”，而在“统一协议下是否完整覆盖 ref 的阶段语义与关键时序”。

## 6. 现状分级（可直接用于排期）

### 6.1 已完成（可作为基线）

1. PlanetX 服务端插件已接入统一大厅。
2. PlanetX 客户端页面已可进入并消费状态快照。
3. 核心操作链路（含 recommend）已可走通。
4. 日志、星图、操作栏的主框架已建立。

### 6.2 部分完成（需收敛）

1. 会议流程逻辑存在，但缺显式 `MeetingCheck` 阶段。
2. 玩家步进与可视窗口机制已实现，但与 ref 的位置序列模型需等价验证。
3. 协议迁移已完成，但缺系统化“行为等价”回归用例。

### 6.3 未完成/高风险

1. 阶段机未完全对齐 ref（P0）。
2. 关键时序（会议后检查、终局前后广播顺序）缺专项测试（P1）。
3. 文档层尚缺“迁移后协议语义基准表”（P1）。

## 7. 建议迭代顺序（依赖顺序）

1. 先补服务端 `MeetingCheck` 阶段（`planetx_plugin/src/model.rs`、`planetx_plugin/src/lib.rs`）。
2. 再补客户端 `meeting_check` 阶段显示与操作禁用态（`planetx_op_bar.dart`、`planetx_room_page.dart`）。
3. 增加阶段流转测试：`UserMove -> MeetingProposal -> MeetingPublish -> MeetingCheck -> UserMove/LastMove`。
4. 增加跨圈步进与 last move 用户选择测试，校验与 ref 结果一致。
5. 增加端到端协议回放测试（action -> action_result -> broadcast）覆盖关键路径。
6. 最后再做 UI 精修与规则说明呈现等体验优化，避免在规则差距未收敛时提前美化。

## 8. 验收清单（下一阶段完成标准）

1. `meeting_check` 阶段在服务端状态中可见，客户端可正确渲染。
2. 会议阶段结束后 token 检查结果与罚步逻辑稳定。
3. last move 用户集合在多玩家场景下与 ref 行为一致。
4. 二圈及以后不会错误释放首圈限定的 x clue。
5. `cargo test -p planetx_plugin` 与 `flutter analyze` 均通过。
