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
use rand::SeedableRng;
use serde_json::{Value, json};

use crate::map::{ClueGenerator, Map, Sector, Sectors, SectorType};
use crate::operation::{Operation, OperationResult};
use crate::recommendation::{RecommendOperation, RecommendOperationResult};

pub use model::PlanetXState;

#[derive(Clone)]
pub struct PlanetXGame;

impl PlanetXGame {
    pub fn new() -> Self {
        Self {}
    }

    fn build_runtime_map(state: &PlanetXState) -> Result<Map, game::GameError> {
        if state.map_sectors.is_empty() {
            return Err(game::GameError::State("planetx_state_missing_map".into()));
        }

        let sectors = state
            .map_sectors
            .iter()
            .enumerate()
            .map(|(i, ty)| Sector {
                index: i + 1,
                r#type: ty.clone(),
            })
            .collect::<Vec<_>>();

        Ok(Map {
            r#type: state.map_type.clone(),
            sectors: Sectors { data: sectors },
        })
    }

    fn apply_planetx_operation(
        state: &mut PlanetXState,
        user_id: &str,
        op: &Operation,
    ) -> Result<OperationResult, game::GameError> {
        let current = state
            .current_player()
            .ok_or_else(|| game::GameError::State("planetx_missing_current_player".into()))?;
        if current != user_id {
            return Err(game::GameError::Invalid("planetx_not_current_player".into()));
        }

        let map = Self::build_runtime_map(state)?;

        let result = match op {
            Operation::Survey(s) => {
                if s.sector_type == SectorType::X {
                    return Err(game::GameError::Invalid("planetx_invalid_sector_type".into()));
                }
                let max = state.map_type.sector_count();
                if s.start == 0 || s.start > max || s.end == 0 || s.end > max {
                    return Err(game::GameError::Invalid("planetx_invalid_index".into()));
                }
                let cnt = map.survey_sector(s.start, s.end, &s.sector_type);
                OperationResult::Survey(cnt)
            }
            Operation::Target(t) => {
                let max = state.map_type.sector_count();
                if t.index == 0 || t.index > max {
                    return Err(game::GameError::Invalid("planetx_invalid_index".into()));
                }
                let used = state.player_target_uses.entry(user_id.to_string()).or_insert(0);
                if *used >= 2 {
                    return Err(game::GameError::Invalid("planetx_target_time_exhausted".into()));
                }
                *used += 1;
                OperationResult::Target(map.target_sector(t.index))
            }
            Operation::Research(r) => {
                let clue = state
                    .research_clues
                    .iter()
                    .find(|c| c.index == r.index)
                    .cloned()
                    .ok_or_else(|| game::GameError::Invalid("planetx_invalid_clue".into()))?;
                OperationResult::Research(clue)
            }
            Operation::Locate(l) => {
                let max = state.map_type.sector_count();
                if l.index == 0 || l.index > max {
                    return Err(game::GameError::Invalid("planetx_invalid_index".into()));
                }
                let ok = map.locate_x(l.index, &l.pre_sector_type, &l.next_sector_type);
                OperationResult::Locate(ok)
            }
            Operation::ReadyPublish(_) => {
                return Err(game::GameError::Invalid("planetx_stage_not_supported".into()));
            }
            Operation::DoPublish(_) => {
                return Err(game::GameError::Invalid("planetx_stage_not_supported".into()));
            }
        };

        let step = state.player_steps.entry(user_id.to_string()).or_insert(0);
        *step += 1;
        state
            .player_results
            .entry(user_id.to_string())
            .or_default()
            .push(result.clone());

        if let Some(filter) = state.choice_filters.get_mut(user_id) {
            filter.add_operation(op.clone(), result.clone());
        }

        state.advance_turn();

        Ok(result)
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
        s.turn_order = s.players.clone();
        s.turn_order.sort();
        s.turn_index = 0;
        s.choice_filters = s
            .turn_order
            .iter()
            .map(|id| {
                (
                    id.clone(),
                    crate::map::ChoiceFilter::new(s.map_type.clone(), id.clone()),
                )
            })
            .collect();

        let rng = rand::rngs::SmallRng::seed_from_u64(s.map_seed);
        let generated_map = match Map::new(rng, s.map_type.clone()) {
            Ok(m) => m,
            Err(_) => {
                return ActionResult::Err(game::GameError::Internal(
                    "planetx_map_generation_failed".into(),
                ));
            }
        };
        s.map_sectors = generated_map
            .sectors
            .data
            .iter()
            .map(|sec| sec.r#type.clone())
            .collect();

        let mut clue_gen = ClueGenerator::new(s.map_seed, generated_map.sectors.clone(), s.map_type.clone());
        let (research_clues, _x_clues) = match clue_gen.generate_clues() {
            Ok(v) => v,
            Err(_) => {
                return ActionResult::Err(game::GameError::Internal(
                    "planetx_clue_generation_failed".into(),
                ));
            }
        };
        s.research_clues = research_clues;
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
            return ActionResult::Err(game::GameError::Invalid("planetx_user_not_in_room".into()));
        }

        let action_type = action
            .payload
            .get("type")
            .and_then(|v| v.as_str())
            .ok_or_else(|| game::GameError::Invalid("planetx_invalid_payload".into()));

        let action_type = match action_type {
            Ok(v) => v,
            Err(e) => return ActionResult::Err(e),
        };

        match action_type {
            "planetx_sync" => ActionResult::Ok {
                events: vec![],
                broadcasts: vec![Outbound {
                    target: OutboundTarget::User(action.user_id.clone()),
                    payload: json!({
                        "type": "state",
                        "game": "planetx",
                        "room": ctx.room_id,
                        "event": "sync",
                        "state": s,
                    }),
                }],
            },
            "planetx_op" => {
                if !s.started {
                    return ActionResult::Err(game::GameError::Invalid("planetx_room_not_started".into()));
                }

                let op_value = match action.payload.get("op") {
                    Some(v) => v.clone(),
                    None => {
                        return ActionResult::Err(game::GameError::Invalid(
                            "planetx_invalid_payload".into(),
                        ));
                    }
                };

                let op: Operation = match serde_json::from_value(op_value) {
                    Ok(op) => op,
                    Err(_) => {
                        return ActionResult::Err(game::GameError::Invalid(
                            "planetx_invalid_op".into(),
                        ));
                    }
                };

                let op_result = match Self::apply_planetx_operation(s, &action.user_id, &op) {
                    Ok(r) => r,
                    Err(e) => return ActionResult::Err(e),
                };
                let op_result_json = serde_json::to_value(&op_result).unwrap_or(json!({"error":"planetx_result_encode_failed"}));

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
                                "op": op,
                                "result": op_result_json,
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
            "planetx_recommend" => {
                if !s.started {
                    return ActionResult::Err(game::GameError::Invalid("planetx_room_not_started".into()));
                }

                let op_value = match action.payload.get("op") {
                    Some(v) => v.clone(),
                    None => {
                        return ActionResult::Err(game::GameError::Invalid(
                            "planetx_invalid_payload".into(),
                        ));
                    }
                };

                let recommend_op: RecommendOperation = match serde_json::from_value(op_value) {
                    Ok(op) => op,
                    Err(_) => {
                        return ActionResult::Err(game::GameError::Invalid(
                            "planetx_invalid_payload".into(),
                        ));
                    }
                };

                let result = match recommend_op {
                    RecommendOperation::Count => {
                        let cnt = s
                            .choice_filters
                            .get(&action.user_id)
                            .map(|f| f.len())
                            .unwrap_or(0);
                        RecommendOperationResult::Count(cnt)
                    }
                    RecommendOperation::CanLocate => {
                        let can = s
                            .choice_filters
                            .get(&action.user_id)
                            .map(|f| f.can_locate())
                            .unwrap_or(false);
                        RecommendOperationResult::CanLocate(can)
                    }
                };

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::User(action.user_id.clone()),
                        payload: json!({
                            "type": "planetx_recommend_result",
                            "room": ctx.room_id,
                            "result": result,
                        }),
                    }],
                }
            }
            _ => ActionResult::Err(game::GameError::Invalid(
                "planetx_unknown_action_type".into(),
            )),
        }
    }
}