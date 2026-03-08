use crate::{
    room::{RoomUserOperation, ServerResp, game_state::GameStateResp},
    server_state::{ServerState, User},
};
use socketioxide::{
    SocketIo,
    extract::{Data, SocketRef, State},
};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

pub async fn handle_on_connect(_io: SocketIo, socket: SocketRef, _state: State<StateRef>) {
    info!(ns = "socket.io", ?socket.id, "new client connected");

    socket.on("auth", socket_on_auth);
    socket.on_disconnect(socket_on_disconnect);
    socket.on("room_op", socket_on_room_op);
}
async fn socket_on_auth(socket: SocketRef, state: State<StateRef>, user: Data<User>) {
    state
        .0
        .lock()
        .await
        .upsert_user(socket.id.to_string(), user.0.clone(), socket.clone());
    info!(ns = "socket.io", ?socket.id, "auth {:?}", user.0);
    socket
        .emit("server_resp", &ServerResp::auth_success_version())
        .ok();
}
async fn socket_on_disconnect(socket: SocketRef, state: State<StateRef>) {
    state.0.lock().await.users.remove(socket.id.as_str());
    info!(ns = "socket.io", ?socket.id, "disconnected");
}
async fn socket_on_room_op(
    socket: SocketRef,
    state: State<StateRef>,
    Data::<RoomUserOperation>(op): Data<RoomUserOperation>,
) {
    let user = state
        .lock()
        .await
        .users
        .get(socket.id.as_str())
        .map(|(_, u)| u.clone());
    let Some(user) = user else {
        info!(ns = "socket.io", ?socket.id, "unauthorized room op {:?}", op);
        return;
    };

    info!(?op, ?socket.id, "received room op {:?}", op);

    match state
        .lock()
        .await
        .handle_room_op(socket.clone(), user.clone(), op)
    {
        Ok(resp) => {
            let mut do_resp = false;
            for gs in resp {
                info!(ns = "socket.io", ?socket.id, ?gs, "room op success");

                socket.to(gs.id.clone()).emit("game_state", &gs).await.ok();
                if gs.users.iter().any(|u| u.id == user.id) {
                    socket.emit("game_state", &gs).ok();
                    do_resp = true;
                }
            }
            if !do_resp {
                // no game state to response, empty client game state
                socket.emit("game_state", &GameStateResp::dummy()).ok();
            }
        }

        Err(e) => {
            info!(ns = "socket.io", ?socket.id, ?e, "room op error");
            socket.emit("server_resp", &ServerResp::RoomErrors(e)).ok();
        }
    }
}

pub fn create_state() -> Arc<Mutex<ServerState>> {
    Arc::new(Mutex::new(ServerState::new()))
}

pub type StateRef = Arc<Mutex<ServerState>>;

pub fn register_state_manager(state: StateRef, _io: SocketIo) {
    // Spawn a background task for periodic maintenance / broadcasting.
    tokio::task::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
        loop {
            interval.tick().await;
            let _guard = state.lock().await;
            // TODO: broadcast periodic state, clean up stale games, etc.
        }
    });
}
