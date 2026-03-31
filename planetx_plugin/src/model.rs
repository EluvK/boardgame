use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanetXState {
    pub started: bool,
    pub players: Vec<String>,
    pub seq: u64,
    pub last_actor: Option<String>,
    pub last_payload: Option<Value>,
}

impl PlanetXState {
    pub fn new() -> Self {
        Self {
            started: false,
            players: Vec::new(),
            seq: 0,
            last_actor: None,
            last_payload: None,
        }
    }
}