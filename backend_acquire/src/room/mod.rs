pub mod game_state;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ServerResp {
    Version(String),
    RejoinRoom(String),
    RoomErrors(RoomError),
}

impl ServerResp {
    pub fn auth_success_version() -> Self {
        ServerResp::Version("0.1.0".to_string())
    }
    pub fn rejoin_room(room_id: String) -> Self {
        Self::RejoinRoom(room_id)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoomUserOperation {
    Create,
    Edit(EditRoomInfo),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct EditRoomInfo {
    pub room_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoomError {
    RoomNotFound,
    RoomStarted,
    RoomFull,
    UserNotFoundInRoom,
}
