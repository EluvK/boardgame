# Acquire 服务端实现清单（规则映射版）

本清单把规则说明书映射到当前代码，目标是让后续开发按条推进并可验证。

关联文档：
- 规则说明书：.github/guides/acquire-rulebook.zh-CN.md
- 当前实现：
  - acquire_plugin/src/lib.rs（模块入口与导出）
  - acquire_plugin/src/model.rs（状态结构定义）
  - acquire_plugin/src/engine.rs（规则与动作处理）
  - acquire_plugin/src/tests.rs（回归测试）

## 1. 状态模型（State）

当前结构体：AcquireState（acquire_plugin/src/model.rs）

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
- [x] player_tiles: 手牌（每人 6 张，已支持落子后补牌）
- [x] tile_bag: 板块池（抽牌来源，已支持 draw_tile 消耗）
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

- [x] draw_tile
  - 已支持显式动作；手牌已满/牌袋为空会拒绝

## 3. 规则校验（Validation）

### 3.1 已落地

- [x] 最少 2 人才能开始行动
- [x] 非当前玩家不可行动
- [x] 阶段校验：place/buy 不可越阶段
- [x] 买股数量限制：0..=3
- [x] 现金不足拒绝购买
- [x] 重复坐标落子拒绝
- [x] 落子必须来自手牌（tile_not_in_hand）

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
  - 全部活跃公司安全且无法新建公司（已改为版图可行性判定，不再仅看槽位）
- [x] 终局清算（发奖+抛售）

## 4. 价格系统（Pricing）

当前：

- [x] 动态股价已接入（公司等级 + 规模）
- [x] 非零 buy 已移除 `__generic__` 兼容买入路径

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
- [x] draw_tile_ok（对操作者）

建议标准事件（待补）：

- [x] game_started
- [x] tile_placed（由 place_ok 承载）
- [x] company_founded
- [x] company_expanded
- [x] merge_started（由 merge_pending 承载）
- [x] survivor_selected（由 merge_resolved.survivor 承载）
- [x] bonus_paid
- [x] shares_converted
- [x] shares_sold
- [x] hand_refilled
- [x] end_declared
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
- [x] expand_absorbs_adjacent_independent_component
- [x] declare_end_allowed_when_all_safe_and_no_founding_opportunity
- [x] declare_end_rejected_when_founding_opportunity_exists
- [x] declare_end_ignores_inactive_company_holdings_in_liquidation
- [x] on_join_deals_initial_six_tiles_per_player
- [x] draw_tile_requires_non_full_hand_and_draws_when_available
- [x] place_rejected_when_tile_not_in_hand

下一批必须补：

- [x] 邻接分类测试（4 类）
- [x] 安全公司不可被并
- [x] 平规模由当前玩家选择存续
- [x] 头名/次名奖金平手分配（覆盖已强化）
- [x] 股票出售与兑换约束
- [x] 终局触发与清算现金排名
- [x] 快照恢复后回合一致性

## 7. 建议实施顺序（可直接执行）

1. merge_stock_decision 细粒度化 ✅
- 支持同一被并公司在一个结算窗口内混合 sell/trade/hold（而非一次性决策）。

2. 开局规则对齐
- 对齐规则书第 1、2 节的先手决定与开局流程（当前仍是最小闭环实现）。

3. 事件语义补齐 ✅
- 视客户端需求拆分 bonus_paid / shares_converted / shares_sold / hand_refilled / end_declared。

4. 测试补齐（已完成两项，长局补牌待补）
- 强化奖金平手分配覆盖 ✅
- 增加快照恢复后一致性用例 ✅
- 增加牌袋耗尽与长局补牌一致性用例。

## 8. 本周最小里程碑（建议）

- M1: 完成 merge_stock_decision 细粒度化。✅
- M2: 完成开局规则（先手/初始流程）对齐。
- M3: 完成事件拆分并与客户端约定字段。✅（服务端事件已补齐）
- M4: 完成快照恢复与长局补牌回归测试。（快照恢复✅；长局补牌待补）

## 9. 本次收尾状态（2026-03-20）

- [x] 并购插件单文件已拆分为模块化结构（lib/model/engine/tests）。
- [x] 重构后回归测试通过（acquire_plugin: 18 passed / 0 failed）。
- [x] 交接文档已同步到模块化路径。

## 10. 今日收尾状态（2026-03-23）

- [x] merge_stock_decision 已支持同一被并公司分步处理（sell/trade/hold 混合，非一次性决策）。
- [x] 事件语义已补齐：game_started/company_expanded/bonus_paid/shares_sold/shares_converted/hand_refilled/end_declared。
- [x] 测试新增 4 项：邻接四分类、分步并购股票决策、快照恢复回合一致性、奖金平手分配强化。
- [x] acquire_plugin 回归通过（22 passed / 0 failed）。
