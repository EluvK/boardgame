use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::game::{Action, ActionCtx, ActionResult, Game, GameId, GameState, RoomId, UserId};

/// A Room holds a single game instance and its mutable state plus list of players.
pub struct Room {
    pub id: RoomId,
    pub game: Arc<dyn Game>,
    state: Mutex<Box<dyn GameState>>,
    meta: Mutex<RoomMeta>,
}

struct RoomMeta {
    users: HashSet<UserId>,
    ready_users: HashSet<UserId>,
    started: bool,
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
    pub ready_count: usize,
    pub started: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ReadyStatus {
    pub room: RoomId,
    pub game_id: GameId,
    pub player_count: usize,
    pub ready_count: usize,
    pub min_players: usize,
    pub max_players: usize,
    pub started: bool,
    pub all_ready: bool,
    pub ready_users: Vec<UserId>,
}

impl Room {
    pub async fn new(id: RoomId, game: Arc<dyn Game>, opts: Option<Value>) -> anyhow::Result<Self> {
        let state = game.create_initial_state(opts).await;
        Ok(Self {
            id,
            game,
            state: Mutex::new(state),
            meta: Mutex::new(RoomMeta {
                users: HashSet::new(),
                ready_users: HashSet::new(),
                started: false,
            }),
        })
    }

    pub async fn join(&self, user: UserId) -> ActionResult {
        let mut state_guard = self.state.lock().await;
        let mut meta_guard = self.meta.lock().await;
        if meta_guard.started && !meta_guard.users.contains(&user) {
            return ActionResult::Err(crate::game::GameError::Invalid(
                "room_already_started".to_string(),
            ));
        }
        meta_guard.users.insert(user.clone());
        meta_guard.ready_users.remove(&user);

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
        let mut meta_guard = self.meta.lock().await;
        meta_guard.users.remove(user);
        meta_guard.ready_users.remove(user);

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
        let started = self.meta.lock().await.started;
        if !started {
            return ActionResult::Err(crate::game::GameError::Invalid(
                "room_not_started_wait_for_all_ready".to_string(),
            ));
        }

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
        self.meta.lock().await.users.len()
    }

    pub async fn users(&self) -> Vec<UserId> {
        let mut users: Vec<UserId> = self.meta.lock().await.users.iter().cloned().collect();
        users.sort();
        users
    }

    pub async fn has_user(&self, user: &UserId) -> bool {
        self.meta.lock().await.users.contains(user)
    }

    pub async fn is_empty(&self) -> bool {
        self.meta.lock().await.users.is_empty()
    }

    pub async fn is_started(&self) -> bool {
        self.meta.lock().await.started
    }

    pub async fn set_ready(&self, user: &UserId, ready: bool) -> Result<ReadyStatus, String> {
        let (status, should_call_start) = {
            let mut meta = self.meta.lock().await;
            if !meta.users.contains(user) {
                return Err("not_in_room".to_string());
            }

            if meta.started {
                return Ok(self.ready_status_from_meta(&meta));
            }

            if ready {
                meta.ready_users.insert(user.clone());
            } else {
                meta.ready_users.remove(user);
            }

            let min_players = self.game.descriptor().min_players;
            let all_ready = !meta.users.is_empty() && meta.ready_users.len() == meta.users.len();
            let enough_players = meta.users.len() >= min_players;
            let should_call_start = all_ready && enough_players;
            if should_call_start {
                meta.started = true;
            }

            (self.ready_status_from_meta(&meta), should_call_start)
        };

        if should_call_start {
            let mut state_guard = self.state.lock().await;
            let ctx = ActionCtx {
                room_id: self.id.clone(),
                session_id: None,
                now_ts: chrono::Utc::now().timestamp_millis() as u64,
                ext: None,
            };

            if let ActionResult::Err(err) = self.game.on_start(&ctx, state_guard.as_mut()).await {
                let mut meta = self.meta.lock().await;
                meta.started = false;
                return Err(format!("room_start_failed: {err}"));
            }
        }

        Ok(status)
    }

    pub async fn ready_status(&self) -> ReadyStatus {
        let meta = self.meta.lock().await;
        self.ready_status_from_meta(&meta)
    }

    fn ready_status_from_meta(&self, meta: &RoomMeta) -> ReadyStatus {
        let mut ready_users: Vec<UserId> = meta.ready_users.iter().cloned().collect();
        ready_users.sort();

        ReadyStatus {
            room: self.id.clone(),
            game_id: self.game.descriptor().id.clone(),
            player_count: meta.users.len(),
            ready_count: meta.ready_users.len(),
            min_players: self.game.descriptor().min_players,
            max_players: self.game.descriptor().max_players,
            started: meta.started,
            all_ready: !meta.users.is_empty() && meta.ready_users.len() == meta.users.len(),
            ready_users,
        }
    }

    pub async fn summary(&self) -> RoomSummary {
        let meta = self.meta.lock().await;
        RoomSummary {
            id: self.id.clone(),
            game_id: self.game.descriptor().id.clone(),
            player_count: meta.users.len(),
            ready_count: meta.ready_users.len(),
            started: meta.started,
        }
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
            let summary = room.summary().await;
            out.push(RoomSummary {
                id,
                game_id,
                player_count: summary.player_count,
                ready_count: summary.ready_count,
                started: summary.started,
            });
        }
        out
    }

    pub async fn room_summary(&self, id: &RoomId) -> Option<RoomSummary> {
        let room = self.get_room(id).await?;
        Some(room.summary().await)
    }

    pub async fn leave_all_rooms_for_user(&self, user: &UserId) -> Vec<RoomId> {
        let rooms: Vec<(RoomId, Arc<Room>)> = {
            let guard = self.inner.lock().await;
            guard
                .iter()
                .map(|(id, room)| (id.clone(), room.clone()))
                .collect()
        };

        let mut emptied_rooms = Vec::new();
        for (room_id, room) in rooms {
            if !room.has_user(user).await {
                continue;
            }

            let _ = room.leave(user).await;
            if room.is_empty().await {
                self.remove_room(&room_id).await;
                emptied_rooms.push(room_id);
            }
        }

        emptied_rooms
    }

    pub async fn find_user_room(&self, user: &UserId) -> Option<RoomId> {
        let rooms: Vec<(RoomId, Arc<Room>)> = {
            let guard = self.inner.lock().await;
            guard
                .iter()
                .map(|(id, room)| (id.clone(), room.clone()))
                .collect()
        };

        for (room_id, room) in rooms {
            if room.has_user(user).await {
                return Some(room_id);
            }
        }

        None
    }

    pub async fn reclaim_empty_rooms(&self) -> Vec<RoomId> {
        let rooms: Vec<(RoomId, Arc<Room>)> = {
            let guard = self.inner.lock().await;
            guard
                .iter()
                .map(|(id, room)| (id.clone(), room.clone()))
                .collect()
        };

        let mut reclaimed = Vec::new();
        for (room_id, room) in rooms {
            if room.is_empty().await {
                self.remove_room(&room_id).await;
                reclaimed.push(room_id);
            }
        }

        reclaimed
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
