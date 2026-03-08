use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use socketioxide::extract::SocketRef;
use tracing::info;

use crate::room::{
    RoomError, RoomUserOperation, ServerResp, game_state::{GameStateResp, ServerGameState}
};

pub struct ServerState {
    pub users: HashMap<String, (SocketRef, User)>,
    pub state_data: HashMap<String, (GameStateResp, ServerGameState)>,
}

impl ServerState {
    pub fn new() -> Self {
        Self {
            users: HashMap::new(),
            state_data: HashMap::new(),
        }
    }

    pub fn upsert_user(&mut self, socket_id: String, user: User, socket: SocketRef) {
        self.iter_game_state().for_each(|(room_id, gs)| {
            if gs.users.iter().any(|u| u.id == user.id) {
                info!("upsert user: {} in room: {}", user.id, room_id);
                socket.leave_all();
                socket
                    .emit("server_resp", &ServerResp::rejoin_room(room_id.clone()))
                    .ok();
                socket.join(room_id.clone());
            }
        });
        self.users.insert(socket_id, (socket, user));
    }

    pub fn handle_room_op(&mut self, socket: SocketRef, user:User, room_op: RoomUserOperation) -> Result<Vec<GameStateResp>, RoomError> {
        todo!()
    }
}

impl ServerState {
    pub fn iter_game_state(&self) -> impl Iterator<Item = (&String, &GameStateResp)> {
        self.state_data.iter().map(|(k, v)| (k, &v.0))
    }
    pub fn iter_all(&self) -> impl Iterator<Item = (&String, (&GameStateResp, &ServerGameState))> {
        self.state_data.iter().map(|(k, v)| (k, (&v.0, &v.1)))
    }
    pub fn iter_mut_game_state(&mut self) -> impl Iterator<Item = (&String, &mut GameStateResp)> {
        self.state_data.iter_mut().map(|(k, v)| (k, &mut v.0))
    }

    pub fn iter_mut_all(
        &mut self,
    ) -> impl Iterator<Item = (&String, (&mut GameStateResp, &mut ServerGameState))> {
        self.state_data
            .iter_mut()
            .map(|(k, v)| (k, (&mut v.0, &mut v.1)))
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct User {
    pub id: String, // some rand uuid for each device.
    pub name: String,
}
