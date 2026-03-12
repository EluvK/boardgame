use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use socketioxide::{
    SocketIo,
    extract::{Data, SocketRef, State},
};
use tokio::sync::Mutex;
use tracing::info;

use crate::game::{Action, ActionResult, Outbound, OutboundTarget};
use crate::room::RoomManager;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct UserInfo {
    pub id: String,
    pub name: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JoinRoomReq {
    pub room: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActionReq {
    pub room: String,
    pub action: Action,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateRoomReq {
    pub room: String,
    pub game_id: String,
    pub opts: Option<Value>,
    pub auto_join: Option<bool>,
}

/// Server-side state stored in socket.io State<T>
pub struct ServerState {
    /// map socket_id -> (SocketRef, user_id)
    pub users: HashMap<String, (SocketRef, String)>,
    pub room_manager: Arc<RoomManager>,
}

impl ServerState {
    pub fn new(room_manager: Arc<RoomManager>) -> Self {
        Self {
            users: HashMap::new(),
            room_manager,
        }
    }
}

pub type StateRef = Arc<Mutex<ServerState>>;

const HEALTH_OK: &str = "ok";

#[allow(unused_braces)]
#[salvo::handler]
pub async fn health() -> &'static str {
    HEALTH_OK
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    /// http path where socket.io is mounted, e.g. "/socket.io"
    pub path: String,
    /// socket.io namespace to register handlers on, e.g. "/" or "/acquire"
    pub namespace: String,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".into(),
            port: 17980,
            path: "/socket.io".into(),
            namespace: "/".into(),
        }
    }
}

/// Start the Socket.IO server using the provided `RoomManager` and configuration.
pub async fn run_server(
    config: ServerConfig,
    room_manager: Arc<RoomManager>,
) -> anyhow::Result<()> {
    use salvo::{Listener, Router, Server, conn::TcpListener, prelude::TowerLayerCompat};
    use socketioxide::SocketIo;
    use tracing::info;
    let log_config = crate::logs::LogConfig::default();
    let _g = crate::logs::enable_log(&log_config)?;

    info!("starting server_with_acquire on {}:{}", config.host, config.port);
    // health handler is defined in this module
    let state = Arc::new(Mutex::new(ServerState::new(room_manager)));

    let (layer, io) = SocketIo::builder().with_state(state.clone()).build_layer();

    // register namespace handlers
    // Box::leak the namespace string to obtain a 'static str for the Socket.IO API
    let ns_static: &'static str = Box::leak(config.namespace.into_boxed_str());
    io.ns(ns_static, |io: SocketIo, socket, state: State<StateRef>| {
        handle_on_connect(io, socket, state)
    });

    // background maintenance task
    let _state_clone = state.clone();
    tokio::task::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
        loop {
            interval.tick().await;
            let _guard = _state_clone.lock().await;
            // TODO: periodic maintenance, cleanup stale sessions, metrics
        }
    });

    let layer = tower::ServiceBuilder::new()
        .layer(tower_http::cors::CorsLayer::permissive())
        .layer(layer)
        .compat();

    let router = Router::with_path(&config.path).hoop(layer).goal(health);

    let bind_addr = format!("{}:{}", config.host, config.port);
    info!("binding server to {}", bind_addr);
    let bind_addr_static: &'static str = Box::leak(bind_addr.into_boxed_str());
    let acceptor = TcpListener::new(bind_addr_static).bind().await;
    Server::new(acceptor).serve(router).await;

    Ok(())
}

pub async fn handle_on_connect(_io: SocketIo, socket: SocketRef, _state: State<StateRef>) {
    info!(ns = "socket.io", ?socket.id, "client connected");

    socket.on("auth", socket_on_auth);
    socket.on("list_games", socket_on_list_games);
    socket.on("list_rooms", socket_on_list_rooms);
    socket.on("create_room", socket_on_create_room);
    socket.on("join_room", socket_on_join_room);
    socket.on("leave_room", socket_on_leave_room);
    socket.on("action", socket_on_action);
    socket.on_disconnect(socket_on_disconnect);
}

async fn socket_on_list_games(socket: SocketRef, state: State<StateRef>) {
    let rm = state.lock().await.room_manager.clone();
    let games = rm.list_games().await;
    socket
        .emit(
            "list_games_result",
            &serde_json::json!({"ok": true, "games": games}),
        )
        .ok();
}

async fn socket_on_list_rooms(socket: SocketRef, state: State<StateRef>) {
    let rm = state.lock().await.room_manager.clone();
    let rooms = rm.list_rooms().await;
    socket
        .emit(
            "list_rooms_result",
            &serde_json::json!({"ok": true, "rooms": rooms}),
        )
        .ok();
}

async fn socket_on_create_room(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<CreateRoomReq>(req): Data<CreateRoomReq>,
) {
    let user = {
        let guard = state.lock().await;
        guard
            .users
            .get(socket.id.as_str())
            .map(|(_, uid)| uid.clone())
    };

    if user.is_none() {
        socket
            .emit("error", &serde_json::json!({"err":"unauthenticated"}))
            .ok();
        return;
    }

    let rm = state.lock().await.room_manager.clone();

    if rm.get_room(&req.room).await.is_some() {
        socket
            .emit(
                "create_room_result",
                &serde_json::json!({"ok": false, "err": "room_already_exists"}),
            )
            .ok();
        return;
    }

    if !rm.has_game(&req.game_id).await {
        socket
            .emit(
                "create_room_result",
                &serde_json::json!({"ok": false, "err": "game_not_registered", "game_id": req.game_id}),
            )
            .ok();
        return;
    }

    match rm
        .create_room_with_game(req.room.clone(), &req.game_id, req.opts.clone())
        .await
    {
        Ok(room) => {
            let should_auto_join = req.auto_join.unwrap_or(true);
            if should_auto_join {
                let uid = user.unwrap();
                socket.join(req.room.clone());
                let res = room.join(uid).await;
                if let ActionResult::Ok { broadcasts, .. } = res {
                    dispatch_broadcasts(&socket, &state, &req.room, broadcasts).await;
                }
            }

            socket
                .emit(
                    "create_room_result",
                    &serde_json::json!({"ok": true, "room": req.room, "game_id": req.game_id}),
                )
                .ok();
        }
        Err(e) => {
            socket
                .emit(
                    "create_room_result",
                    &serde_json::json!({"ok": false, "err": format!("{}", e)}),
                )
                .ok();
        }
    }
}

async fn socket_on_auth(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<UserInfo>(user): Data<UserInfo>,
) {
    let mut s = state.lock().await;
    s.users
        .insert(socket.id.to_string(), (socket.clone(), user.id.clone()));
    info!(ns = "socket.io", ?socket.id, "auth ok for {}", user.id);
    socket
        .emit("auth_ok", &serde_json::json!({"ok": true}))
        .ok();
}

async fn socket_on_disconnect(socket: SocketRef, state: State<StateRef>) {
    let mut s = state.lock().await;
    s.users.remove(socket.id.as_str());
    info!(ns = "socket.io", ?socket.id, "disconnected");
}

async fn socket_on_join_room(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<JoinRoomReq>(req): Data<JoinRoomReq>,
) {
    let user = {
        let guard = state.lock().await;
        guard
            .users
            .get(socket.id.as_str())
            .map(|(_, uid)| uid.clone())
    };

    let user = match user {
        Some(u) => u,
        None => {
            socket
                .emit("error", &serde_json::json!({"err":"unauthenticated"}))
                .ok();
            return;
        }
    };

    let room_manager = state.lock().await.room_manager.clone();
    match room_manager.get_room(&req.room).await {
        Some(room) => {
            // join the socket.io room
            socket.join(req.room.clone());
            // call room.join game hook
            let res = room.join(user.clone()).await;
            match res {
                ActionResult::Ok { broadcasts, .. } => {
                    // emit a joined ack
                    socket
                        .emit("joined", &serde_json::json!({"room": req.room}))
                        .ok();
                    // dispatch broadcasts
                    dispatch_broadcasts(&socket, &state, &req.room, broadcasts).await;
                }
                ActionResult::Err(e) => {
                    socket
                        .emit(
                            "action_result",
                            &serde_json::json!({"ok": false, "err": format!("{}", e)}),
                        )
                        .ok();
                }
            }
        }
        None => {
            socket
                .emit("error", &serde_json::json!({"err":"room_not_found"}))
                .ok();
        }
    }
}

async fn socket_on_leave_room(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<JoinRoomReq>(req): Data<JoinRoomReq>,
) {
    let user = {
        let guard = state.lock().await;
        guard
            .users
            .get(socket.id.as_str())
            .map(|(_, uid)| uid.clone())
    };

    if user.is_none() {
        socket
            .emit("error", &serde_json::json!({"err":"unauthenticated"}))
            .ok();
        return;
    }

    let user = user.unwrap();
    let rm = state.lock().await.room_manager.clone();
    if let Some(room) = rm.get_room(&req.room).await {
        let _ = room.leave(&user).await;
        socket.leave(req.room.clone());
        socket
            .emit("left", &serde_json::json!({"room": req.room}))
            .ok();
    } else {
        socket
            .emit("error", &serde_json::json!({"err":"room_not_found"}))
            .ok();
    }
}

async fn socket_on_action(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<ActionReq>(req): Data<ActionReq>,
) {
    let user = {
        let guard = state.lock().await;
        guard
            .users
            .get(socket.id.as_str())
            .map(|(_, uid)| uid.clone())
    };

    if user.is_none() {
        socket
            .emit("error", &serde_json::json!({"err":"unauthenticated"}))
            .ok();
        return;
    }

    // ensure the action user_id is the authenticated user
    if req.action.user_id != user.clone().unwrap() {
        socket
            .emit(
                "action_result",
                &serde_json::json!({"ok": false, "err":"user_id_mismatch"}),
            )
            .ok();
        return;
    }

    let rm = state.lock().await.room_manager.clone();
    match rm.apply_action(&req.room, req.action).await {
        Ok(ar) => {
            // send action_result to actor
            socket
                .emit("action_result", &serde_json::json!({"ok": true}))
                .ok();
            // dispatch broadcasts produced by the action
            match ar {
                ActionResult::Ok {
                    events: _,
                    broadcasts,
                } => {
                    dispatch_broadcasts(&socket, &state, &req.room, broadcasts).await;
                }
                ActionResult::Err(e) => {
                    socket
                        .emit(
                            "action_result",
                            &serde_json::json!({"ok": false, "err": format!("{}", e)}),
                        )
                        .ok();
                }
            }
        }
        Err(e) => {
            socket.emit("error", &serde_json::json!({"err": e})).ok();
        }
    }
}

async fn dispatch_broadcasts(
    socket: &SocketRef,
    state: &State<StateRef>,
    room: &str,
    broadcasts: Vec<Outbound>,
) {
    for b in broadcasts {
        match b.target {
            OutboundTarget::All => {
                socket
                    .to(room.to_string())
                    .emit("broadcast", &b.payload)
                    .await
                    .ok();
            }
            OutboundTarget::User(uid) => {
                // find socket for user
                let guard = state.lock().await;
                let found = guard
                    .users
                    .iter()
                    .find_map(|(_, (s, u))| if u == &uid { Some(s.clone()) } else { None });
                if let Some(sref) = found {
                    sref.emit("message", &b.payload).ok();
                }
            }
            OutboundTarget::Others(_) => { /* not implemented yet */ }
            OutboundTarget::Session(_) => { /* not implemented yet */ }
        }
    }
}
