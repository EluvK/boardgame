# Acquire 项目状态快照（2026-03-23）

本文档由仓库根 README 归档而来，用于保留当时联调阶段的细节记录。

## 当前状态（2026-03-23）

项目已从基础联调阶段进入可多人对局阶段，Acquire 的核心回合流程可跑通，且服务端与 Flutter 客户端协议已对齐。

### 已完成

- 房间 ready 门禁：所有玩家 ready 且满足最少人数后才开局。
- 房间内动作门禁：未开局前拒绝 action，返回 `room_not_started_wait_for_all_ready`。
- 进房与重连同步：`join_room` 的 `already_in_room` 分支会回灌最新 `state` 和 `ready_state`。
- 广播修复：`OutboundTarget::All` 会先发给当前 socket，再发房间其他用户，避免 sender 丢首帧。
- buy 协议升级：仅支持 `purchases`（多公司、总计 0..3），移除旧单公司字段语义。
- 无可买自动 pass：当前玩家在 buy 阶段无可买股票时客户端自动提交空购买。
- 地图渲染增强：公司连块视觉、悬停信息、整家公司 hover 联动高亮。
- 发牌随机化：开局时打乱完整坐标序列，后续按序发牌。

### 关键协议点

- 客户端上行
  - `set_ready`: `{ room, ready }`
  - `action`: `{ room, action }`
  - `buy` action payload: `{ type: "buy", purchases: { [companyId]: qty } }`

- 服务端下行
  - `ready_result`
  - `action_result`
  - `broadcast` with `type = state | ready_state`
  - `rooms_updated`

## 快速启动

### 1. 启动服务端

```bash
cargo run -p bg_runtime
```

默认地址：`http://127.0.0.1:17980`，Socket 路径：`/socket.io`。

### 2. 启动 Flutter Web

```bash
flutter run -d chrome
```

在首页填写：

- Server URL: `http://127.0.0.1:17980`
- Display Name: 任意非空

### 3. 双客户端调试（推荐）

已提供 VS Code 方案：[.vscode/launch.json](../../.vscode/launch.json)

- `Chrome Client A`（5001）
- `Chrome Client B`（5002）
- `Dual Chrome Clients`（compound）

## 回归检查清单

### 房间与开局

1. 两个客户端进同一房间。
2. 任一客户端未 ready 时，无法 action。
3. 全员 ready 后收到 `ready_state.started=true` 且广播 `state(event=game_started)`。

### 状态同步

1. 客户端 A 在房内操作。
2. 刷新客户端 B 并重进房间。
3. B 应立即收到当前 `state`（`event=rejoin_sync`）与 `ready_state`。

### buy 阶段

1. 支持跨多个公司购买，总股数 0..3。
2. 现金不足时禁止提交。
3. 无可买公司时自动 pass。

### 发牌随机性

1. 新建房间并开局多次。
2. 观察不同局首轮手牌应明显不同，非固定从 `1A` 开始。

## 编译检查

```bash
cargo check --workspace
flutter analyze
```

当前已知情况：`boardgames_server` 有少量 unused variable warning，不影响运行。

## 关键代码位置

- 开局 ready 门禁与房间元数据：[boardgames_server/src/room.rs](../../boardgames_server/src/room.rs)
- join/rejoin/ready 广播流程：[boardgames_server/src/server.rs](../../boardgames_server/src/server.rs)
- Acquire 规则与发牌随机化：[acquire_plugin/src/engine.rs](../../acquire_plugin/src/engine.rs)
- 客户端房间页面与地图渲染：[lib/src/games/acquire/presentation/acquire_room_page.dart](../../lib/src/games/acquire/presentation/acquire_room_page.dart)
- 客户端动作封装（含 `buy.purchases`）：[lib/src/games/acquire/data/acquire_client.dart](../../lib/src/games/acquire/data/acquire_client.dart)
