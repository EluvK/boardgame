use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::game::{
    Action, ActionCtx, ActionResult, Game, GameId, GameState, RoomId, UserId,
};

/// A Room holds a single game instance and its mutable state plus list of players.
pub struct Room {
    pub id: RoomId,
    pub game: Arc<dyn Game>,
    state: Mutex<Box<dyn GameState>>,
    users: Mutex<HashSet<UserId>>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RegisteredGame {
    pub id: GameId,
    pub name: String,
    pub min_players: usize,
    pub max_players: usize,
    pub version: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RoomSummary {
    pub id: RoomId,
    pub game_id: GameId,
    pub player_count: usize,
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

    pub async fn player_count(&self) -> usize {
        self.users.lock().await.len()
    }
}

/// Manager for rooms. Lightweight registry to create/find rooms.
#[derive(Default, Clone)]
pub struct RoomManager {
    inner: Arc<Mutex<HashMap<RoomId, Arc<Room>>>>,
    games: Arc<Mutex<HashMap<GameId, Arc<dyn Game>>>>,
}

impl RoomManager {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
            games: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn register_game(&self, game: Arc<dyn Game>) {
        let game_id = game.descriptor().id.clone();
        self.games.lock().await.insert(game_id, game);
    }

    pub async fn list_games(&self) -> Vec<RegisteredGame> {
        let guard = self.games.lock().await;
        guard
            .values()
            .map(|g| {
                let d = g.descriptor();
                RegisteredGame {
                    id: d.id.clone(),
                    name: d.name.clone(),
                    min_players: d.min_players,
                    max_players: d.max_players,
                    version: d.version.clone(),
                }
            })
            .collect()
    }

    pub async fn has_game(&self, game_id: &GameId) -> bool {
        self.games.lock().await.contains_key(game_id)
    }

    pub async fn create_room_with_game(
        &self,
        id: RoomId,
        game_id: &GameId,
        opts: Option<Value>,
    ) -> anyhow::Result<Arc<Room>> {
        let game = {
            let guard = self.games.lock().await;
            guard.get(game_id).cloned()
        }
        .ok_or_else(|| anyhow::anyhow!("game not registered: {}", game_id))?;

        self.create_room(id, game, opts).await
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

    pub async fn list_rooms(&self) -> Vec<RoomSummary> {
        let rooms: Vec<(RoomId, Arc<Room>)> = {
            let guard = self.inner.lock().await;
            guard
                .iter()
                .map(|(id, room)| (id.clone(), room.clone()))
                .collect()
        };

        let mut out = Vec::with_capacity(rooms.len());
        for (id, room) in rooms {
            let game_id = room.game.descriptor().id.clone();
            let player_count = room.player_count().await;
            out.push(RoomSummary {
                id,
                game_id,
                player_count,
            });
        }
        out
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
