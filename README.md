# BoardGames Lobby

一个基于 Rust + Flutter 的多人联机桌游项目，当前已经实现 Acquire 游戏的核心玩法与基本交互。

## 项目简介

本仓库包含：

- Rust 服务端运行时与房间系统
- Acquire 游戏规则插件与状态推进引擎
- Flutter 客户端（Web/桌面）

目标是提供可迭代的联机桌游平台基础设施，并在此基础上持续完善 Acquire 的规则完整度、交互体验与对局稳定性。

## 仓库结构

- `acquire_plugin`：Acquire 核心规则与引擎
- `boardgames_server`：通用房间、会话与消息分发逻辑
- `bg_runtime`：服务端可执行入口
- `lib`：Flutter 客户端代码

## 快速开始

### 1. 启动服务端

```bash
cargo run -p bg_runtime
```

默认地址：`http://127.0.0.1:17980`，Socket 路径：`/socket.io`。

### 2. 启动客户端（Web）

```bash
flutter run -d chrome
```

进入首页后填写：

- Server URL：`http://127.0.0.1:17980`
- Display Name：任意非空

## 开发检查

```bash
cargo check --workspace
flutter analyze
```

## 文档入口

- 协作文档索引：`.github/index.md`
- Acquire 规则基线：`.github/guides/acquire-rulebook.zh-CN.md`
- 协议文档：`.github/guides/acquire-client-server-protocol.zh-CN.md`
- 客户端架构：`.github/guides/acquire-client-architecture.zh-CN.md`
- 历史状态快照（由原 README 归档）：`.github/guides/acquire-status-2026-03-23.zh-CN.md`

## 说明

根 README 仅保留项目介绍与快速入口。阶段性进度、回归清单与详细实现记录统一维护在 `.github/guides`。