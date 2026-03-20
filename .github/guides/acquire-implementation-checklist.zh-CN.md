# Acquire 服务端实现清单（规则映射版）

本清单把规则说明书映射到当前代码，目标是让后续开发按条推进并可验证。

关联文档：
- 规则说明书：.github/guides/acquire-rulebook.zh-CN.md
- 当前实现：acquire_plugin/src/lib.rs

## 1. 状态模型（State）

当前结构体：AcquireState（acquire_plugin/src/lib.rs）

- [x] tiles: 已放置坐标集合
- [x] moves: 历史落子（user_id, pos）
- [x] players: 玩家现金
- [x] shares: 玩家持股（已按公司维度存储）
- [x] stock_pool: 公司库存股（每家公司初始 25）
- [x] independent_tiles: 未归属公司的孤立板块集合
- [x] tile_company: 坐标到公司的归属映射
- [x] turn_order: 回合顺序
- [x] current_turn: 当前回合指针
- [x] phase: 回合阶段（place/choose_company/resolve_merge/merge_stock_decision/buy/game_over）
- [x] turn_no: 回合号
- [x] board_cells: 邻接解析能力已具备（坐标解析 + 上下左右邻接）
- [x] companies: 公司状态（激活公司、规模、安全状态）
- [ ] player_tiles: 手牌（每人 6 张）
- [ ] tile_bag: 板块池（抽牌来源）
- [x] merge_context: 合并处理上下文（已支持平规模待决）
- [x] game_end_flag: 可结束状态与终局声明者（game_over + final_standings）

## 2. 动作协议（Action）

已实现动作：

- [x] place
  - 入参：{ type: place, pos }
  - 结果：占格 + 广播 state + 阶段切换到 choose_company/resolve_merge/merge_stock_decision/buy
- [x] buy
  - 入参：{ type: buy, shares }
  - 结果：扣钱 + 加股 + 回合推进
- [x] choose_company
  - 用途：创立公司时由当前玩家选择品牌（已实现显式动作）
- [x] resolve_merge
  - 用途：平规模合并时选择存续公司（已实现最小流程）
- [x] merge_stock_decision
  - 用途：被并公司股票处理（持有/出售/兑换）
- [x] declare_end
  - 用途：满足终局条件时回合内宣告结束

建议补充：

- [ ] draw_tile
  - 可作为显式动作，或由回合结束自动执行

## 3. 规则校验（Validation）

### 3.1 已落地

- [x] 最少 2 人才能开始行动
- [x] 非当前玩家不可行动
- [x] 阶段校验：place/buy 不可越阶段
- [x] 买股数量限制：0..=3
- [x] 现金不足拒绝购买
- [x] 重复坐标落子拒绝

### 3.2 待落地（核心）

- [x] 邻接判定与四种落子结果分类（最小实现）
  - 孤立
  - 创立公司
  - 扩张公司
  - 合并公司
- [x] 安全公司规则（11+ 不可被并，已覆盖多安全公司互并拒绝）
- [x] 公司规模比较与平局决策（已支持同规模存续选择）
- [x] 头名/次名奖金分配（含平手拆分，最小实现）
- [x] 被并公司股票三选一处理（持有/出售/2:1 兑换，最小实现）
- [x] 创立奖励股（若库存>0）
- [x] 终局触发条件
  - 任一公司 >= 41
  - 全部活跃公司安全且无法新建公司（最小实现：无可新建公司槽位）
- [x] 终局清算（发奖+抛售）

## 4. 价格系统（Pricing）

当前：

- [x] 动态股价已接入（公司等级 + 规模）；`__generic__` 兼容路径仍使用 100

待实现：

- [x] 建立公司等级表（低/中/高）
- [x] 建立规模到股价映射函数（已用于 buy）
- [x] 合并/清算时使用当时市价
- [x] 将 shares 从总股数改为按公司维度持股

## 5. 事件流（Event / Broadcast）

当前广播：

- [x] place_ok
- [x] choose_company_required
- [x] company_founded
- [x] merge_pending
- [x] merge_resolved
- [x] merge_stock_decision_required
- [x] merge_stock_decision_applied
- [x] merge_finalized
- [x] turn_advanced
- [x] buy_ok（对操作者）
- [x] final_scored

建议标准事件（待补）：

- [ ] game_started
- [x] tile_placed（由 place_ok 承载）
- [x] company_founded
- [ ] company_expanded（当前由 place_ok + placement 承载，未拆独立事件）
- [x] merge_started（由 merge_pending 承载）
- [x] survivor_selected（由 merge_resolved.survivor 承载）
- [ ] bonus_paid
- [ ] shares_converted
- [ ] shares_sold
- [ ] hand_refilled
- [ ] end_declared
- [x] final_scored

## 6. 测试矩阵（优先级）

当前：

- [x] requires_two_players_before_actions
- [x] enforces_turn_order_and_phase_transition
- [x] buy_limits_and_turn_advance_work
- [x] merge_tie_requires_resolve_then_allows_buy
- [x] choose_company_requires_valid_and_inactive_company
- [x] cannot_merge_multiple_safe_companies
- [x] merge_stock_decision_sell_updates_cash_and_holding
- [x] merge_stock_decision_trade_converts_two_to_one
- [x] declare_end_rejected_when_conditions_not_met
- [x] declare_end_scores_and_sets_winner

下一批必须补：

- [ ] 邻接分类测试（4 类）
- [x] 安全公司不可被并
- [x] 平规模由当前玩家选择存续
- [ ] 头名/次名奖金平手分配（覆盖仍可加强）
- [x] 股票出售与兑换约束
- [x] 终局触发与清算现金排名
- [ ] 快照恢复后回合一致性

## 7. 建议实施顺序（可直接执行）

1. 棋盘与公司模型落地
- 增加 board/companies/stock_pool 数据结构。
- 将 shares 改为按公司维度持有。

2. 落子解析与合并框架
- place 后进入 resolve 子阶段，计算邻接图并产出分类结果。

3. 价格与奖金系统
- 先实现股价函数，再接入 merge 和 end 结算。

4. 股票处理动作
- 完成 merge_stock_decision 的三选一流程和校验。

5. 终局与结算
- declare_end + final_scored 事件。

6. 测试补齐
- 按测试矩阵逐项补齐，保证每条核心规则至少 1 正例 + 1 反例。

## 8. 本周最小里程碑（建议）

- M1: 完成棋盘邻接与公司模型。
- M2: 完成创立/扩张/合并基础判定。
- M3: 完成奖金与股票处理。
- M4: 完成终局结算与回归测试。
