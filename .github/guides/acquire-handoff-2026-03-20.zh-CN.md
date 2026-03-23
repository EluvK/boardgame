# Acquire 服务端问题清单与交接纪要（2026-03-20）

> 文档状态：历史归档（只读）。
>
> 时效性说明：本文件中的“待修/下次顺序”仅代表 2026-03-20 当日状态，可能已被后续实现覆盖。
> 当前进度请以 `.github/guides/acquire-implementation-checklist.zh-CN.md` 为准。
>
> 日常开发请优先维护以下文档：
> - .github/guides/acquire-rulebook.zh-CN.md
> - .github/guides/acquire-implementation-checklist.zh-CN.md

本文件用于跨会话交接，包含：
- 当前实现状态（已完成）
- 与规则书对照后发现的问题（待修）
- 已验证结果（测试）
- 下次会话建议执行顺序

关联文件：
- 规则书：.github/guides/acquire-rulebook.zh-CN.md
- 实现清单：.github/guides/acquire-implementation-checklist.zh-CN.md
- 服务端实现：
	- acquire_plugin/src/lib.rs（模块入口与导出）
	- acquire_plugin/src/model.rs（状态结构）
	- acquire_plugin/src/engine.rs（规则与动作处理）
	- acquire_plugin/src/tests.rs（回归测试）

## 1. 当前已完成（服务端）

0. 代码结构重构（本次已完成）
- 已将原先单文件实现拆分为 constants/model/engine/tests 四个模块。
- 对外 API 保持不变：仍通过 AcquireGame 作为插件入口。
- 已验证重构后行为一致，测试通过。

1. 游戏主流程最小闭环
- 已支持阶段：place / choose_company / resolve_merge / merge_stock_decision / buy / game_over。
- 已支持多人回合与阶段校验。

2. 公司与股票核心
- 已支持创立公司（choose_company 显式选择品牌）。
- 已支持扩张、合并触发、平规模存续选择。
- 已支持扩张与合并时吸收相邻孤立板块（公司规模修正）。
- 已支持被并股票处理（hold / sell / trade 2:1）。
- 已支持库存股校验与扣减。

3. 价格与结算
- 已支持公司等级 + 规模价格函数。
- 已支持 merge 奖金（头名/次名，含平手最小实现）。
- 已支持 declare_end 与 final_scored。
- 已修正 declare_end 条件："无法再建立新公司"改为版图可行性判定（不再仅看公司槽位）。
- 已修正终局清算：仅对激活公司持仓按有效价格结算，未激活公司不计价。

4. 手牌与补牌最小闭环
- 已新增 tile_bag / player_tiles 状态。
- 已在 on_join 时为每位玩家发 6 张起始牌。
- 已支持 draw_tile 动作（手牌已满/牌袋为空时会拒绝）。
- 已支持落子后自动补牌到 6 张。
- 已收紧落子：place 必须使用手牌中的 tile（tile_not_in_hand）。

5. 买股规则收紧
- 已移除非零 __generic__ 买股路径。
- 非零 buy 必须显式指定活跃公司；shares=0 仍可用于跳过买股并推进回合。

6. 测试状态
- acquire_plugin 测试：18 passed / 0 failed（截至本次更新）。

## 2. 规则对照问题现状（已修/待修）

### P0（高优先级，影响规则正确性）

1) 扩张/合并时未吸收相邻孤立板块
- 状态：已修复。
- 说明：扩张与合并完成后，都会吸收与落子相邻的孤立板块连通分量并更新公司规模。

2) 终局条件第 2 条实现不等价
- 状态：已修复。
- 说明：已改为“版图是否仍存在可创立机会（FoundCandidate）”判定。

3) 终局清算可能对未激活公司股票给出错误估值
- 状态：已修复。
- 说明：size<2 时价格为 0，且清算仅对激活公司持仓计价。

### P1（中优先级，影响规则完整性）

4) buy 允许 __generic__ 兼容路径
- 状态：已修复。
- 说明：非零 buy 必须指定活跃公司，__generic__ 不再可用于非零买入。

5) 初始设置与补牌未实现
- 状态：部分修复。
- 已完成：player_tiles / tile_bag、on_join 发 6 张、draw_tile、落子后自动补牌、place 手牌校验。
- 仍待做：
	- 先手决定流程与规则书一致性（当前仍非完整规则流程）。
	- 开局阶段（如起始落子顺序/公开信息）与规则书第 1 节逐条对齐。

6) merge_stock_decision 为每家公司一次性决策
- 状态：待修。
- 现状：仍是“同一被并公司一次决策”。
- 影响：尚不支持同公司股票细粒度混合处理（部分卖/部分换/部分留）。

### P2（低优先级，事件语义与可观测性）

7) 部分建议事件未独立发出
- 例如：bonus_paid / shares_converted / shares_sold / end_declared 仍未拆独立事件。
- 当前可由 state 快照推导，但对客户端动画与审计不够友好。

## 3. 已知实现约束（本次决定）

1. 先服务端优先，不做客户端落地。
2. 当前实现目标是“可玩最小闭环”，并非完整桌游规则复刻。
3. choose_company 已改为显式动作，不再自动选首个未激活公司。

## 4. 下次会话推荐执行顺序（更新）

1. 修 P1-6：merge_stock_decision 细粒度化（同公司支持混合 sell/trade/hold）。
2. 继续补 P1-5：对齐规则书的先手决定与开局流程（不仅是发牌与补牌）。
3. 补 P2 事件：拆分 bonus_paid / shares_converted / shares_sold / end_declared。
4. 增加针对新手牌机制的回归测试：
- 多玩家长回合补牌一致性。
- 牌袋耗尽场景。
- draw_tile 与 place/buy 阶段交互边界。

## 5. 快速恢复上下文（下次开工可直接用）

1. 先运行：cargo test -p acquire_plugin
2. 关键入口：acquire_plugin/src/lib.rs（对外入口） + acquire_plugin/src/engine.rs 的 handle_action
3. 关键状态：acquire_plugin/src/model.rs 中 AcquireState（companies / tile_company / independent_tiles / merge_settlement / phase / tile_bag / player_tiles）
4. 参考文档：
- .github/guides/acquire-rulebook.zh-CN.md
- .github/guides/acquire-implementation-checklist.zh-CN.md
- 本文件 .github/guides/acquire-handoff-2026-03-20.zh-CN.md
