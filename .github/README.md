# .github 文档索引与维护约定

本目录用于保存项目协作文档。为减少重复和过期信息，按“长期维护”与“历史归档”区分。

## 文档必要性结论

| 文档 | 当前结论 | 维护方式 |
|---|---|---|
| guides/acquire-rulebook.zh-CN.md | 保留（必要） | 作为规则基线，按规则理解更新 |
| guides/acquire-implementation-checklist.zh-CN.md | 保留（必要） | 作为实现主清单，持续更新勾选状态 |
| guides/acquire-handoff-2026-03-20.zh-CN.md | 保留（可选） | 历史交接快照，不作为主清单维护 |
| prompts/plan-boardgame.prompt.md | 保留（必要） | 作为多游戏统一架构目标说明 |

## 使用建议

1. 日常开发优先查看：
   - guides/acquire-rulebook.zh-CN.md
   - guides/acquire-implementation-checklist.zh-CN.md
2. `acquire-handoff-2026-03-20.zh-CN.md` 仅用于追溯历史决策，不再作为待办来源。
3. 若后续有新的交接纪要，建议放到 `guides/` 并在标题标注日期，同时在本文件中注明是否“归档”或“持续维护”。