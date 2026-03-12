use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::game::{
    self, Action, ActionCtx, ActionResult, Game, GameState, Outbound, RoomId, UserId,
};

/// A Room holds a single game instance and its mutable state plus list of players.
pub struct Room {
    pub id: RoomId,
    pub game: Arc<dyn Game>,
    state: Mutex<Box<dyn GameState>>,
    users: Mutex<HashSet<UserId>>,
}

impl Room {
    pub async fn new(id: RoomId, game: Arc<dyn Game>, opts: Option<Value>) -> anyhow::Result<Self> {
        let state = game.create_initial_state(opts).await;
        Ok(Self {
            id,
            game,
            state: Mutex::new(state),
            users: Mutex::new(HashSet::new()),
        })
    }

    pub async fn join(&self, user: UserId) -> ActionResult {
        let mut state_guard = self.state.lock().await;
        let mut users_guard = self.users.lock().await;
        users_guard.insert(user.clone());

        let ctx = ActionCtx {
            room_id: self.id.clone(),
            session_id: None,
            now_ts: chrono::Utc::now().timestamp_millis() as u64,
            ext: None,
        };

        // call game on_join hook
        self.game.on_join(&ctx, state_guard.as_mut(), user).await
    }

    pub async fn leave(&self, user: &UserId) -> ActionResult {
        let mut state_guard = self.state.lock().await;
        let mut users_guard = self.users.lock().await;
        users_guard.remove(user);

        let ctx = ActionCtx {
            room_id: self.id.clone(),
            session_id: None,
            now_ts: chrono::Utc::now().timestamp_millis() as u64,
            ext: None,
        };

        self.game
            .on_leave(&ctx, state_guard.as_mut(), user.clone())
            .await
    }

    pub async fn apply_action(&self, action: Action) -> ActionResult {
        let mut state_guard = self.state.lock().await;

        let ctx = ActionCtx {
            room_id: self.id.clone(),
            session_id: None,
            now_ts: chrono::Utc::now().timestamp_millis() as u64,
            ext: None,
        };

        self.game
            .handle_action(&ctx, state_guard.as_mut(), action)
            .await
    }

    pub async fn snapshot(&self) -> anyhow::Result<Vec<u8>> {
        let state_guard = self.state.lock().await;
        state_guard.snapshot()
    }
}

/// Manager for rooms. Lightweight registry to create/find rooms.
#[derive(Default, Clone)]
pub struct RoomManager {
    inner: Arc<Mutex<HashMap<RoomId, Arc<Room>>>>,
}

impl RoomManager {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn create_room(
        &self,
        id: RoomId,
        game: Arc<dyn Game>,
        opts: Option<Value>,
    ) -> anyhow::Result<Arc<Room>> {
        let room = Arc::new(Room::new(id.clone(), game, opts).await?);
        self.inner.lock().await.insert(id.clone(), room.clone());
        Ok(room)
    }

    pub async fn get_room(&self, id: &RoomId) -> Option<Arc<Room>> {
        self.inner.lock().await.get(id).cloned()
    }

    pub async fn remove_room(&self, id: &RoomId) {
        self.inner.lock().await.remove(id);
    }

    /// Apply action in a room and return the ActionResult for the caller to dispatch broadcasts.
    pub async fn apply_action(
        &self,
        room_id: &RoomId,
        action: Action,
    ) -> Result<ActionResult, String> {
        let room = self
            .get_room(room_id)
            .await
            .ok_or_else(|| "room not found".to_string())?;
        Ok(room.apply_action(action).await)
    }
}
