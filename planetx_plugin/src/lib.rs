mod model;
pub mod map;
pub mod operation;
pub mod recommendation;

use std::sync::OnceLock;

use async_trait::async_trait;
use boardgames_server::game::{
    self, Action, ActionCtx, ActionResult, Game, GameDescriptor, GameState, Outbound,
    OutboundTarget,
};
use serde_json::{Value, json};

pub use model::PlanetXState;

#[derive(Clone)]
pub struct PlanetXGame;

impl PlanetXGame {
    pub fn new() -> Self {
        Self {}
    }
}

#[async_trait]
impl GameState for PlanetXState {
    fn apply_event(&mut self, _ev: &game::Event) {
        // PlanetX M1 keeps logic minimal and does not replay events.
    }

    fn snapshot(&self) -> anyhow::Result<Vec<u8>> {
        Ok(serde_json::to_vec(self)?)
    }

    fn restore(&mut self, data: &[u8]) -> anyhow::Result<()> {
        *self = serde_json::from_slice(data)?;
        Ok(())
    }
}

#[async_trait]
impl Game for PlanetXGame {
    fn descriptor(&self) -> &GameDescriptor {
        static DESC: OnceLock<GameDescriptor> = OnceLock::new();
        DESC.get_or_init(|| GameDescriptor {
            id: "planetx".into(),
            name: "Planet X (migration stub)".into(),
            min_players: 2,
            max_players: 6,
            version: "0.1".into(),
        })
    }

    async fn create_initial_state(&self, _opts: Option<Value>) -> Box<dyn GameState> {
        Box::new(PlanetXState::new())
    }

    async fn on_join(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        user: String,
    ) -> ActionResult {
        let any = state as &mut dyn std::any::Any;
        let s = match any.downcast_mut::<PlanetXState>() {
            Some(s) => s,
            None => {
                return ActionResult::Err(game::GameError::Internal("state type mismatch".into()));
            }
        };

        if !s.players.iter().any(|u| u == &user) {
            s.players.push(user.clone());
            s.players.sort();
        }

        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![Outbound {
                target: OutboundTarget::All,
                payload: json!({
                    "type": "state",
                    "game": "planetx",
                    "room": ctx.room_id,
                    "event": "player_joined",
                    "by": user,
                    "state": s,
                }),
            }],
        }
    }

    async fn on_start(&self, ctx: &ActionCtx, state: &mut dyn GameState) -> ActionResult {
        let any = state as &mut dyn std::any::Any;
        let s = match any.downcast_mut::<PlanetXState>() {
            Some(s) => s,
            None => {
                return ActionResult::Err(game::GameError::Internal("state type mismatch".into()));
            }
        };

        s.started = true;
        s.seq += 1;

        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![Outbound {
                target: OutboundTarget::All,
                payload: json!({
                    "type": "state",
                    "game": "planetx",
                    "room": ctx.room_id,
                    "event": "game_started",
                    "state": s,
                }),
            }],
        }
    }

    async fn handle_action(
        &self,
        ctx: &ActionCtx,
        state: &mut dyn GameState,
        action: Action,
    ) -> ActionResult {
        let any = state as &mut dyn std::any::Any;
        let s = match any.downcast_mut::<PlanetXState>() {
            Some(s) => s,
            None => {
                return ActionResult::Err(game::GameError::Internal("state type mismatch".into()));
            }
        };

        if !s.players.iter().any(|u| u == &action.user_id) {
            return ActionResult::Err(game::GameError::Invalid("user_not_in_room".into()));
        }

        if !s.started {
            return ActionResult::Err(game::GameError::Invalid("room_not_started".into()));
        }

        s.seq += 1;
        s.last_actor = Some(action.user_id.clone());
        s.last_payload = Some(action.payload.clone());

        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![
                Outbound {
                    target: OutboundTarget::User(action.user_id.clone()),
                    payload: json!({
                        "type": "planetx_op_result",
                        "room": ctx.room_id,
                        "seq": s.seq,
                        "ok": true,
                    }),
                },
                Outbound {
                    target: OutboundTarget::All,
                    payload: json!({
                        "type": "state",
                        "game": "planetx",
                        "room": ctx.room_id,
                        "event": "action_applied",
                        "state": s,
                    }),
                },
            ],
        }
    }
}