use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, OnceLock};

use boardgames_server::game::{
    self, Action, ActionCtx, ActionResult, Game, GameDescriptor, GameState, Outbound,
    OutboundTarget,
};

#[derive(Clone)]
pub struct AcquireGame;

impl AcquireGame {
    pub fn new() -> Self {
        AcquireGame {}
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcquireState {
    // minimal state: placed tiles and players
    pub tiles: HashSet<String>,
    pub moves: Vec<(String, String)>,  // (user_id, pos)
    pub players: HashMap<String, i64>, // simple cash tracking
}

impl AcquireState {
    pub fn snapshot_state(&self) -> Value {
        json!({
            "tiles": self.tiles.iter().cloned().collect::<Vec<_>>(),
            "moves": self.moves,
            "players": self.players,
        })
    }
}

#[async_trait]
impl GameState for AcquireState {
    fn apply_event(&mut self, _ev: &game::Event) {
        // for this minimal implementation we do not support event sourcing
    }

    fn snapshot(&self) -> anyhow::Result<Vec<u8>> {
        let v = serde_json::to_vec(&self.snapshot_state())?;
        Ok(v)
    }

    fn restore(&mut self, data: &[u8]) -> anyhow::Result<()> {
        let v: Value = serde_json::from_slice(data)?;
        if let Some(arr) = v.get("tiles").and_then(|t| t.as_array()) {
            self.tiles = arr
                .iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect();
        }
        if let Some(arr) = v.get("moves").and_then(|m| m.as_array()) {
            self.moves = arr
                .iter()
                .filter_map(|it| {
                    if let Some(user) = it.get(0).and_then(|x| x.as_str()) {
                        if let Some(pos) = it.get(1).and_then(|x| x.as_str()) {
                            return Some((user.to_string(), pos.to_string()));
                        }
                    }
                    None
                })
                .collect();
        }
        Ok(())
    }
}

#[async_trait]
impl Game for AcquireGame {
    fn descriptor(&self) -> &GameDescriptor {
        static DESC: OnceLock<GameDescriptor> = OnceLock::new();
        DESC.get_or_init(|| GameDescriptor {
            id: "acquire".into(),
            name: "Acquire (minimal)".into(),
            min_players: 2,
            max_players: 6,
            version: "0.1".into(),
        })
    }

    async fn create_initial_state(&self, _opts: Option<Value>) -> Box<dyn GameState> {
        Box::new(AcquireState {
            tiles: HashSet::new(),
            moves: vec![],
            players: HashMap::new(),
        })
    }

    async fn handle_action(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        action: Action,
    ) -> ActionResult {
        // downcast state to AcquireState using Any
        let any = state as &mut dyn std::any::Any;
        let s = match any.downcast_mut::<AcquireState>() {
            Some(s) => s,
            None => {
                return ActionResult::Err(game::GameError::Internal("state type mismatch".into()));
            }
        };

        // simple action schema: { "type": "place", "pos": "A1" }
        let ty = action
            .payload
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        match ty {
            "place" => {
                if let Some(pos) = action.payload.get("pos").and_then(|v| v.as_str()) {
                    // naive placement: reject if already placed
                    if s.tiles.contains(pos) {
                        return ActionResult::Err(game::GameError::Invalid(
                            "tile already placed".into(),
                        ));
                    }
                    s.tiles.insert(pos.to_string());
                    s.moves.push((action.user_id.clone(), pos.to_string()));
                    // ensure player has an entry
                    s.players.entry(action.user_id.clone()).or_insert(6000);

                    // broadcast updated state to room
                    let payload =
                        json!({"type":"state","state": s.snapshot_state(), "by": action.user_id});
                    let out = Outbound {
                        target: OutboundTarget::All,
                        payload,
                    };
                    return ActionResult::Ok {
                        events: vec![],
                        broadcasts: vec![out],
                    };
                }
                ActionResult::Err(game::GameError::Invalid("missing pos".into()))
            }
            "buy" => {
                // simple buy: {"type":"buy","shares":1}
                let shares = action
                    .payload
                    .get("shares")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                if shares <= 0 {
                    return ActionResult::Err(game::GameError::Invalid("invalid shares".into()));
                }
                let player_cash = s.players.entry(action.user_id.clone()).or_insert(6000);
                let cost = shares * 100; // flat price in this stub
                if *player_cash < cost {
                    return ActionResult::Err(game::GameError::Invalid("not_enough_cash".into()));
                }
                *player_cash -= cost;
                let payload = json!({"type":"buy_ok","user": action.user_id, "shares": shares, "cash": *player_cash});
                let out = Outbound {
                    target: OutboundTarget::User(action.user_id.clone()),
                    payload,
                };
                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![out],
                }
            }
            _ => ActionResult::Err(game::GameError::Invalid("unknown action type".into())),
        }
    }
}

// (no extra downcast helpers needed; GameState extends Any in the server crate)
