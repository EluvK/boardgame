# Acquire 前后端交互协议（Socket.IO）

本文档用于对齐 Acquire 服务端与 Flutter 客户端的交互细节，作为客户端开发的单一参考。

适用范围：
- 运行时：boardgames_server + acquire_plugin
- 传输层：Socket.IO
- 文档版本：v0.2（对应 2026-03-23 服务端实现）

## 1. 连接与通用事件

客户端连接后，建议按以下顺序调用：

1. `auth`
2. `list_games`
3. `list_rooms`
4. `create_room` 或 `join_room`
5. `action`（游戏动作）

### 1.1 客户端 -> 服务端

- `auth`
  - payload:
  ```json
  {
    "id": "u1",
    "name": "Alice"
  }
  ```

- `list_games`
  - payload: `{}`

- `list_rooms`
  - payload: `{}`

- `create_room`
  - payload:
  ```json
  {
    "room": "acq-001",
    "game_id": "acquire",
    "opts": null,
    "auto_join": true
  }
  ```

- `join_room`
  - payload:
  ```json
  {
    "room": "acq-001"
  }
  ```

- `leave_room`
  - payload:
  ```json
  {
    "room": "acq-001"
  }
  ```

- `action`
  - payload:
  ```json
  {
    "room": "acq-001",
    "action": {
      "id": "a-1001",
      "user_id": "u1",
      "payload": { "type": "place", "pos": "1A" },
      "seq": null,
      "meta": null
    }
  }
  ```

### 1.2 服务端 -> 客户端

- 请求响应类：
  - `auth_ok`
  - `list_games_result`
  - `list_rooms_result`
  - `get_room_result`
  - `create_room_result`
  - `close_room_result`
  - `joined`
  - `left`
  - `action_result`
  - `error`

- 推送类：
  - `rooms_updated`（大厅房间列表变更）
  - `broadcast`（房间级广播）
  - `message`（用户定向消息，如 buy_ok、draw_tile_ok、hand_refilled）

## 2. Acquire Action 协议

`action.action.payload.type` 支持如下动作。

### 2.1 `place`

```json
{ "type": "place", "pos": "1A" }
```

约束：
- 当前阶段必须为 `place`
- 必须轮到当前玩家
- 坐标必须合法
- 坐标必须在该玩家手牌内
- 不可重复落子

### 2.2 `buy`

```json
{ "type": "buy", "shares": 0 }
```
或
```json
{ "type": "buy", "company": "Worldwide", "shares": 2 }
```

约束：
- 当前阶段必须为 `buy`
- `shares` 只能是 0..=3
- 非 0 买入必须提供活跃 `company`
- 现金与库存股必须足够

说明：
- `shares = 0` 合法，表示跳过买股并推进回合。

### 2.3 `choose_company`

```json
{ "type": "choose_company", "company": "Worldwide" }
```

约束：
- 当前阶段必须为 `choose_company`
- 公司名必须合法且当前未激活

### 2.4 `resolve_merge`

```json
{ "type": "resolve_merge", "survivor": "Worldwide" }
```

约束：
- 当前阶段必须为 `resolve_merge`
- `survivor` 必须在服务端给出的 allowed_survivors 内

### 2.5 `merge_stock_decision`

```json
{ "type": "merge_stock_decision", "company": "Sackson", "mode": "hold" }
```

```json
{ "type": "merge_stock_decision", "company": "Sackson", "mode": "sell", "shares": 1 }
```

```json
{ "type": "merge_stock_decision", "company": "Sackson", "mode": "trade", "shares": 2 }
```

约束：
- 当前阶段必须为 `merge_stock_decision`
- `company` 必须是当前被并公司之一，且该玩家有待处理决策
- `mode` 仅支持 `hold | sell | trade`
- `trade` 至少需要可兑换 2 股

说明（已支持细粒度）：
- 同一被并公司可分步处理，不要求一次性清空。
- 当该玩家该公司持股归零时，服务端自动清 pending。
- 全部 pending 清空后，服务端自动完成并购并切回 `buy`。

### 2.6 `declare_end`

```json
{ "type": "declare_end" }
```

约束：
- 当前阶段必须为 `place` 或 `buy`
- 必须满足终局条件

### 2.7 `draw_tile`

```json
{ "type": "draw_tile" }
```

约束：
- 手牌未满（< 6）
- 牌袋非空

## 3. 状态快照结构（state）

服务端大部分广播都会携带：

```json
{
  "type": "state",
  "state": { ...AcquireState..., "current_player": "u1" },
  "event": "place_ok"
}
```

关键字段：
- `tiles`: 已落子坐标集合
- `moves`: 历史动作（user_id, pos）
- `players`: 玩家现金
- `shares`: 玩家持股（按公司）
- `stock_pool`: 公司库存股
- `player_tiles`: 玩家手牌
- `tile_bag`: 牌袋剩余
- `independent_tiles`: 孤立牌块
- `tile_company`: 坐标到公司归属
- `companies`: 激活公司信息（tiles/safe）
- `merge_context`: 平规模待决上下文
- `merge_settlement`: 并购股票处理上下文
- `founding_context`: 创立公司待决上下文
- `game_over`: 是否结束
- `final_standings`: 终局排名
- `turn_order`, `current_turn`, `current_player`
- `phase`: `place | choose_company | resolve_merge | merge_stock_decision | buy | game_over`
- `turn_no`

前端约定：
- 以 `state.phase` 作为主状态机驱动 UI。
- 仅在 `current_player == self_user_id` 时放开操作按钮。

## 4. Acquire 业务事件（payload.event）

房间广播 `broadcast` 中常见 `event`：

- `game_started`
- `player_joined`
- `place_ok`
- `choose_company_required`
- `company_founded`
- `company_expanded`
- `merge_pending`
- `merge_stock_decision_required`
- `merge_resolved`
- `shares_sold`
- `shares_converted`
- `merge_stock_decision_applied`
- `merge_finalized`
- `bonus_paid`
- `turn_advanced`
- `end_declared`
- `final_scored`

辅助字段（按事件出现）：
- `placement`: `isolated | found_pending | expand:<company> | merge_pending | merge_pending_stock:<survivor> | merge:<survivor>`
- `company`: 股票决策中处理的公司
- `survivor`: 合并存续公司
- `needs_stock_decision`: resolve_merge 后是否仍需股票处理
- `bonus_paid`: 头名/次名奖金明细
- `sold_shares`, `sold_cash`
- `traded_old_shares`, `traded_new_shares`
- `winner`: 终局赢家
- `by`: 操作者 user_id

## 5. 用户定向消息（message）

### 5.1 `buy_ok`

```json
{
  "type": "buy_ok",
  "user": "u1",
  "company": "Worldwide",
  "unit_price": 200,
  "shares": 2,
  "holding": 3,
  "cash": 5600
}
```

### 5.2 `draw_tile_ok`

```json
{
  "type": "draw_tile_ok",
  "user": "u1",
  "tile": "7D",
  "hand": ["1A", "2B"],
  "remaining": 77
}
```

### 5.3 `hand_refilled`

```json
{
  "type": "hand_refilled",
  "user": "u1",
  "hand_count": 6,
  "remaining": 77
}
```

## 6. 常见错误码（err）

说明：`action_result` 失败时，`err` 来自服务端 `GameError::Invalid/State` 的字符串。

高频错误：
- `not_enough_players_min_2`
- `game_already_over`
- `not_your_turn`
- `phase_mismatch_expected_place`
- `phase_mismatch_expected_buy`
- `phase_mismatch_expected_choose_company`
- `phase_mismatch_expected_resolve_merge`
- `phase_mismatch_expected_merge_stock_decision`
- `phase_mismatch_expected_place_or_buy`
- `invalid_position`
- `tile_not_in_hand`
- `tile already placed`
- `missing pos`
- `invalid shares`
- `missing_company_for_buy`
- `company_not_active`
- `not_enough_stock_pool`
- `company_not_tradeable`
- `not_enough_cash`
- `missing_company`
- `unknown_company`
- `company_already_active`
- `missing_survivor`
- `invalid_merge_survivor`
- `cannot_merge_multiple_safe_companies`
- `invalid_loser_company`
- `no_pending_decision_for_user_company`
- `trade_requires_at_least_two_shares`
- `not_enough_stock_pool_for_trade`
- `invalid_merge_stock_mode`
- `end_conditions_not_met`
- `hand_already_full`
- `tile_bag_empty`
- `unknown action type`

## 7. Flutter 客户端落地建议

1. 建立三层模型：
- SocketEvent DTO（原始包）
- AcquireMessage（按 type/event 归类）
- UI State（页面可消费）

2. 以状态快照为准：
- 不做本地规则推演，所有规则以后端 `state` 为真值。

3. 事件仅作交互提示：
- `event` 用于 toast/动画/日志，不作为状态真值来源。

4. 错误码字典化：
- 将 `err` -> 本地 i18n key 映射，统一弹层样式。

5. 回合按钮显隐：
- 统一由 `phase + current_player == self_user` 决定。

## 8. 变更管理

建议后续每次协议变更都更新：
- 本文档版本号
- 新增/修改字段
- 兼容策略（客户端最低兼容版本）
