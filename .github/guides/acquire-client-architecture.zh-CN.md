# Acquire 客户端架构设计（Flutter）

本文档用于约束 boardgame_acquire 客户端目录与职责边界，目标是：
- 支持多个游戏并存（不把具体游戏逻辑塞进 room 公共层）
- 对齐服务端协议（Socket.IO + state 快照真值）
- 让后续新增游戏时只新增目录，不改动既有游戏页面

## 1. 设计原则

1. room 层只做会话和分发，不承载具体游戏 UI 与规则。
2. 游戏实现按 gameId 分目录，游戏之间互不依赖。
3. 状态真值来自服务端 state 快照，前端不做规则推演。
4. 公共能力（网络、存储、设备身份）放在 src/api 与 src/utils。
5. 兼容优先：目录迁移时保留必要的 export 过渡层，避免一次性大规模改 import。

## 2. 当前推荐目录

```text
lib/
  main.dart
  src/
    api/
      lobby_api.dart
    home/
      home_page.dart
    room/
      room_detail_page.dart              # 入口页（壳），仅组装 session + router
      room_session.dart                  # 房间会话参数模型
      room_game_router.dart              # 按 gameId 分发到具体游戏页面
      unsupported_game_room_page.dart    # 未接入游戏的占位页
    games/
      acquire/
        data/
          acquire_client.dart            # Acquire 专属动作网关（基于 LobbyApi.sendAction）
          acquire_models.dart            # Acquire 协议 DTO / state 解析
        presentation/
          acquire_room_page.dart         # Acquire 房间页面（UI + 交互）
    models/
      acquire_models.dart                # 过渡 export，避免旧引用立即失效
      lobby_models.dart
    utils/
      device_identity.dart
      lobby_preferences.dart
      storage_box.dart
```

## 3. 分层职责

### 3.1 src/room（公共房间层）

- room_detail_page.dart
  - 接收 roomId/gameId/userId/api。
  - 创建 RoomSession。
  - 交给 RoomGameRouter 分发。

- room_session.dart
  - 封装跨游戏共享的会话字段：roomId/gameId/userId/api/onLeaveRoom。

- room_game_router.dart
  - 统一路由入口。
  - 仅做 gameId -> 页面映射，不写业务逻辑。

- unsupported_game_room_page.dart
  - 当 gameId 没有接入客户端时，给出可退回/可离房的兜底页。

### 3.2 src/games/<gameId>（游戏实现层）

每个游戏建议最少包含：
- data：协议 DTO、序列化、事件归类。
- presentation：页面、组件、交互。

Acquire 当前已落地：
- data/acquire_models.dart
- presentation/acquire_room_page.dart

后续可扩展：
- application：状态组装、消息归并、命令封装。
- widgets：可复用游戏组件。

### 3.3 src/api（传输层）

- lobby_api.dart 负责 socket 连接、大厅事件、房间基础动作（join/leave）、通用 sendAction。
- 不承载任何具体游戏的常量、动作名、规则语义。
- 游戏页面只依赖 api 的能力，不直接处理 socket 原始对象。

### 3.4 src/games/<gameId>/data（游戏网关层）

- acquire_client.dart：
  - 封装 Acquire 专属动作（place/buy/choose_company/resolve_merge/merge_stock_decision/declare_end/draw_tile）。
  - 维护 Acquire 专属静态字典（如公司列表）。
  - 内部调用 LobbyApi.sendAction，避免页面拼装协议细节。

## 4. 新增游戏接入流程（标准步骤）

1. 在 src/games 下新增目录：games/<new_game_id>/。
2. 建 data 模型：解析该游戏 state 与 message。
3. 建 presentation 页面：<new_game_id>_room_page.dart。
4. 在 room_game_router.dart 增加 case '<new_game_id>'。
5. 如果需要公共组件，先放在 games/<new_game_id>/widgets；跨游戏复用后再抽到 src/common（后续新增）。

## 5. 命名规范

1. 文件命名：snake_case。
2. 页面类命名：<GameName>RoomPage。
3. data 模型后缀：StateSnapshot / StateEnvelope。
4. router 分发 key 必须与服务端 game_id 一致。

## 6. 状态与交互规范

1. phase 与 current_player 共同决定可操作性。
2. action 失败统一由 api 抛错，页面只做展示。
3. broadcast 的 state 为真值；message 用于提示和辅助信息。
4. 页面内不缓存可推导的规则状态，优先从最新快照读取。

## 7. 迁移策略（已执行）

1. Acquire 页面从 room_detail_page.dart 迁移到 games/acquire/presentation/acquire_room_page.dart。
2. room_detail_page.dart 改为入口壳，不含具体游戏逻辑。
3. models/acquire_models.dart 保留为 export 过渡层，后续可在全量引用迁移后删除。
4. LobbyApi 中的 Acquire 常量与动作方法已迁移到 games/acquire/data/acquire_client.dart。

## 8. 本次会话压缩总结

1. 完成 room 层去业务化：room_detail_page 仅做 session + router，新增 unsupported 页作为多游戏兜底。
2. 完成 Acquire 页面迁移：并购 UI 与协议模型都进入 games/acquire 目录。
3. 完成 API 解耦：LobbyApi 只保留通用传输与大厅能力，Acquire 专属动作抽到 AcquireClient。
4. 保留兼容过渡：models/acquire_models.dart 通过 export 兼容历史引用。
5. 验证通过：flutter analyze 无错误。

## 9. 后续建议

1. 将 Acquire 页面继续拆分为多个小组件（状态区、操作区、玩家区、日志区）。
2. 引入 application 层（Controller/VM）减少页面状态变量数量。
3. 建立 src/common（或 src/shared）承载跨游戏可复用组件与错误映射。
