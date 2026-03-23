# .github 文档索引与维护约定

本目录用于保存项目协作文档。为减少重复和过期信息，按“长期维护”与“历史归档”区分。

最后整理时间：2026-03-23

## 文档状态总览

| 文档 | 状态 | 用途 | 维护方式 |
|---|---|---|---|
| guides/acquire-rulebook.zh-CN.md | 持续维护 | Acquire 规则基线 | 规则理解变更时更新 |
| guides/acquire-implementation-checklist.zh-CN.md | 持续维护 | 服务端实现进度主清单 | 研发完成后及时勾选与补注 |
| guides/acquire-client-server-protocol.zh-CN.md | 持续维护 | 前后端协议单一参考 | 协议字段/事件变更时同步更新版本 |
| guides/acquire-client-architecture.zh-CN.md | 持续维护 | Flutter 客户端分层与目录约束 | 架构调整时同步更新 |
| guides/acquire-handoff-2026-03-20.zh-CN.md | 历史归档 | 会话交接快照 | 只读，不作为当前待办来源 |
| prompts/plan-boardgame.prompt.md | 持续维护 | 跨游戏长期目标说明 | 目标阶段变化时更新 |

## 日常阅读顺序（推荐）

1. guides/acquire-rulebook.zh-CN.md
2. guides/acquire-implementation-checklist.zh-CN.md
3. guides/acquire-client-server-protocol.zh-CN.md
4. guides/acquire-client-architecture.zh-CN.md

## 维护约定

1. 交接纪要必须带日期，且默认标记为“历史归档”。
2. 历史归档文档中的待办仅代表当时快照，不应直接作为当前任务来源。
3. 如果同一主题出现多份文档冲突，以“持续维护”文档为准。