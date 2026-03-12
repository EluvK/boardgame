// deps: async-trait, serde, serde_json, thiserror (建议)
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

pub type GameId = String;
pub type RoomId = String;
pub type UserId = String;
pub type SessionId = String;
pub type SeqNo = u64;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Action {
    pub id: String, // 幂等 id（客户端或网关生成）
    pub user_id: UserId,
    pub payload: Value,      // 游戏自定义载荷（建议用 enum 或 schema）
    pub seq: Option<SeqNo>,  // 可选序列号
    pub meta: Option<Value>, // 可选元数据（trace/ts 等）
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub ty: String,
    pub payload: Value,
    pub meta: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ActionResult {
    Ok {
        events: Vec<Event>,
        broadcasts: Vec<Outbound>,
    },
    Err(GameError),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Outbound {
    pub target: OutboundTarget,
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OutboundTarget {
    All,
    Others(Vec<UserId>),
    User(UserId),
    Session(SessionId),
}

#[derive(thiserror::Error, Debug, Clone, Serialize, Deserialize)]
pub enum GameError {
    #[error("invalid action: {0}")]
    Invalid(String),
    #[error("state error: {0}")]
    State(String),
    #[error("internal: {0}")]
    Internal(String),
    #[error("retryable: {0}")]
    Retryable(String),
}

/// 运行时上下文，RoomManager/Transport 可传入实现
#[derive(Clone)]
pub struct ActionCtx {
    pub room_id: RoomId,
    pub session_id: Option<SessionId>,
    pub now_ts: u64,
    // 可扩展字段：storage handle, metrics handle, trace id 等
    pub ext: Option<Arc<dyn std::any::Any + Send + Sync>>,
}

/// 负责保存/恢复/序列化游戏状态的 trait
#[async_trait]
pub trait GameState: std::any::Any + Send + Sync {
    /// 应用事件到内存状态（用于事件溯源或重放）
    fn apply_event(&mut self, ev: &Event);

    /// 导出快照（二进制，供存储）
    fn snapshot(&self) -> anyhow::Result<Vec<u8>>;

    /// 从快照恢复
    fn restore(&mut self, data: &[u8]) -> anyhow::Result<()>;
}

/// 描述游戏元数据（名字、玩家人数、版本等）
#[derive(Clone)]
pub struct GameDescriptor {
    pub id: GameId,
    pub name: String,
    pub min_players: usize,
    pub max_players: usize,
    pub version: String,
}

/// 最核心的 Game trait：只关注游戏逻辑与 lifecycle
#[async_trait]
pub trait Game: Send + Sync + 'static {
    /// 元数据
    fn descriptor(&self) -> &GameDescriptor;

    /// 创建初始状态（新房间或重置）
    async fn create_initial_state(&self, opts: Option<Value>) -> Box<dyn GameState>;

    /// 处理客户端/玩家的 action，返回产生的 events 与 outbound 消息
    /// 注意：为简化一致性，建议房间层以单线程/单任务序列化调用此方法（即同一房间并发被限制）
    async fn handle_action(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        action: Action,
    ) -> ActionResult;

    /// 可选的 lifecycle 钩子：玩家加入
    async fn on_join(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        user: UserId,
    ) -> ActionResult {
        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![],
        }
    }

    /// 可选的 lifecycle 钩子：玩家离开
    async fn on_leave(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        user: UserId,
    ) -> ActionResult {
        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![],
        }
    }

    /// 可选的定期 tick（比如计时器）
    async fn on_tick(&self, _ctx: &ActionCtx, _state: &mut dyn GameState) -> Option<ActionResult> {
        None
    }
}
