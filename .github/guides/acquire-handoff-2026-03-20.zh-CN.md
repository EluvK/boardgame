# Acquire 服务端问题清单与交接纪要（2026-03-20）

本文件用于跨会话交接，包含：
- 当前实现状态（已完成）
- 与规则书对照后发现的问题（待修）
- 已验证结果（测试）
- 下次会话建议执行顺序

关联文件：
- 规则书：.github/guides/acquire-rulebook.zh-CN.md
- 实现清单：.github/guides/acquire-implementation-checklist.zh-CN.md
- 服务端实现：acquire_plugin/src/lib.rs

## 1. 当前已完成（服务端）

1. 游戏主流程最小闭环
- 已支持阶段：place / choose_company / resolve_merge / merge_stock_decision / buy / game_over。
- 已支持多人回合与阶段校验。

2. 公司与股票核心
- 已支持创立公司（choose_company 显式选择品牌）。
- 已支持扩张、合并触发、平规模存续选择。
- 已支持被并股票处理（hold / sell / trade 2:1）。
- 已支持库存股校验与扣减。

3. 价格与结算
- 已支持公司等级 + 规模价格函数。
- 已支持 merge 奖金（头名/次名，含平手最小实现）。
- 已支持 declare_end 与 final_scored。

4. 测试状态
- acquire_plugin 测试：11 passed / 0 failed（截至本纪要）。

## 2. 规则对照发现的问题（全部待修）

### P0（高优先级，影响规则正确性）

1) 扩张/合并时未吸收相邻孤立板块
- 现状：扩张只把当前落子并入公司，未把相邻孤立块一并并入。
- 影响：公司规模偏小，进一步影响安全公司判定、价格、合并结果。
- 位置：acquire_plugin/src/lib.rs（PlacementKind::Expand 分支）。

2) 终局条件第 2 条实现不等价
- 现状：用“无可用新公司槽位”近似“无法再建立新公司”。
- 影响：可能提前或延后允许 declare_end。
- 位置：acquire_plugin/src/lib.rs（can_declare_end）。

3) 终局清算可能对未激活公司股票给出错误估值
- 现状：清算遍历所有持仓，可能对 size=0 的公司按 tier 得到非零价格。
- 影响：现金结算不符合规则。
- 位置：acquire_plugin/src/lib.rs（share_price_for_size / settle_endgame）。

### P1（中优先级，影响规则完整性）

4) buy 允许 __generic__ 兼容路径
- 现状：允许不指定活跃公司直接买“泛化股票”。
- 影响：偏离“只能买活跃公司股票”。
- 位置：acquire_plugin/src/lib.rs（buy 分支 company == __generic__ 逻辑）。

5) 初始设置与补牌未实现
- 现状：无 player_tiles / tile_bag；先手非抽牌判定；无 draw_tile。
- 影响：与规则书第 1、2 节存在结构性差距。

6) merge_stock_decision 为每家公司一次性决策
- 现状：对同一家被并公司做一次决策后即移除 pending。
- 影响：不支持更细粒度的“同一家股票部分卖/部分换/部分留”。

### P2（低优先级，事件语义与可观测性）

7) 部分建议事件未独立发出
- 例如：bonus_paid / shares_converted / shares_sold / end_declared 仍未拆独立事件。
- 当前可由 state 快照推导，但对客户端动画与审计不够友好。

## 3. 已知实现约束（本次决定）

1. 先服务端优先，不做客户端落地。
2. 当前实现目标是“可玩最小闭环”，并非完整桌游规则复刻。
3. choose_company 已改为显式动作，不再自动选首个未激活公司。

## 4. 下次会话推荐执行顺序

1. 修 P0-1：扩张/合并吸收孤立块（先保证公司规模正确）。
2. 修 P0-3：清算只对活跃公司（或有明确规则支持的公司）按有效价格结算。
3. 修 P0-2：把“无法再建立新公司”改为版图可行性判定，而非槽位判定。
4. 修 P1-4：移除或收紧 __generic__ 买股路径。
5. 加测试：
- 扩张吸收孤立块。
- 终局条件“全安全且无法新建”正反例。
- 清算不对未激活公司错误计价。

## 5. 快速恢复上下文（下次开工可直接用）

1. 先运行：cargo test -p acquire_plugin
2. 关键入口：acquire_plugin/src/lib.rs 的 handle_action
3. 关键状态：AcquireState（companies / tile_company / independent_tiles / merge_settlement / phase）
4. 参考文档：
- .github/guides/acquire-rulebook.zh-CN.md
- .github/guides/acquire-implementation-checklist.zh-CN.md
- 本文件 .github/guides/acquire-handoff-2026-03-20.zh-CN.md
