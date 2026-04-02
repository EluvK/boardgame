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
use crate::model::PlanetXStage;
use crate::operation::{Operation, OperationResult, ResearchOperation};
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

        if !Self::op_allowed_in_stage(&state.game_stage, op) {
            return Err(game::GameError::Invalid("planetx_invalid_move_in_stage".into()));
        }

        if matches!(op, Operation::Research(_))
            && state
                .player_results
                .get(user_id)
                .and_then(|v| v.last())
                .is_some_and(|last| {
                    matches!(
                        last,
                        OperationResult::Research(clue)
                            if !matches!(clue.index, crate::map::ClueEnum::X1 | crate::map::ClueEnum::X2)
                    )
                })
        {
            return Err(game::GameError::Invalid(
                "planetx_research_continuously".into(),
            ));
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
                if !Self::in_visible_range(state.start_index, state.end_index, s.start, max)
                    || !Self::in_visible_range(state.start_index, state.end_index, s.end, max)
                {
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
                if !Self::in_visible_range(state.start_index, state.end_index, t.index, max) {
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
            Operation::ReadyPublish(rp) => {
                let tokens = state
                    .user_tokens
                    .get_mut(user_id)
                    .ok_or_else(|| game::GameError::State("planetx_user_tokens_missing".into()))?;
                let mut edited_tokens = tokens.clone();
                for sector in &rp.sectors {
                    let token = edited_tokens
                        .iter_mut()
                        .find(|t| t.is_not_used(sector))
                        .ok_or_else(|| game::GameError::Invalid("planetx_token_not_enough".into()))?;
                    token.set_to_be_placed();
                }
                *tokens = edited_tokens;
                OperationResult::ReadyPublish(rp.sectors.len())
            }
            Operation::DoPublish(dp) => {
                let max = state.map_type.sector_count();
                if dp.index == 0 || dp.index > max {
                    return Err(game::GameError::Invalid("planetx_invalid_index".into()));
                }
                if state.revealed_sector_indexes.contains(&dp.index) {
                    return Err(game::GameError::Invalid("planetx_sector_already_revealed".into()));
                }

                let tokens = state
                    .user_tokens
                    .get_mut(user_id)
                    .ok_or_else(|| game::GameError::State("planetx_user_tokens_missing".into()))?;
                let mut edited_tokens = tokens.clone();

                if let Some(token) = edited_tokens
                    .iter_mut()
                    .find(|t| t.is_ready_published(&dp.sector_type))
                {
                    token.set_published(dp.index);
                } else if let Some(token) = edited_tokens
                    .iter_mut()
                    .find(|t| !t.placed && t.r#type == dp.sector_type)
                {
                    token.set_to_be_placed().set_published(dp.index);
                } else {
                    return Err(game::GameError::Invalid("planetx_token_not_enough".into()));
                }

                if !state.revealed_sector_indexes.contains(&dp.index) {
                    state.revealed_sector_indexes.push(dp.index);
                }
                *tokens = edited_tokens;

                OperationResult::DoPublish((dp.index, dp.sector_type.clone()))
            }
        };

        let previous_step = state.player_steps.get(user_id).copied().unwrap_or(0);
        let op_cost = Self::operation_cost(op, state.map_type.sector_count());
        if op_cost > 0 {
            let step = state.player_steps.entry(user_id.to_string()).or_insert(0);
            *step += op_cost;
        }
        state
            .player_results
            .entry(user_id.to_string())
            .or_default()
            .push(result.clone());

        if let Some(filter) = state.choice_filters.get_mut(user_id) {
            filter.add_operation(op.clone(), result.clone());
        }

        if matches!(state.game_stage, PlanetXStage::UserMove) {
            Self::unlock_x_clues_on_pass(state, previous_step, op_cost);
        }

        match state.game_stage {
            PlanetXStage::UserMove => {
                if Self::should_enter_last_move(&result) {
                    state.game_stage = PlanetXStage::LastMove;
                    state.terminator_step = state.player_steps.get(user_id).copied().unwrap_or(0);
                    state.last_move_users = Self::build_last_move_users(state, user_id);
                    if let Some(next_uid) = state.last_move_users.first().cloned() {
                        if let Some(idx) = state.turn_order.iter().position(|u| u == &next_uid) {
                            state.turn_index = idx;
                        }
                    } else {
                        Self::finalize_game(state, &map);
                    }
                } else if Self::is_meeting_triggered(state, previous_step, op_cost) {
                    state.game_stage = PlanetXStage::MeetingProposal;
                    state.meeting_ready_users.clear();
                    state.meeting_published_users.clear();
                } else {
                    state.advance_turn();
                    state.recompute_visible_range();
                }
            }
            PlanetXStage::LastMove => {
                state.last_move_users.retain(|u| u != user_id);
                if let Some(next_uid) = state.last_move_users.first().cloned() {
                    if let Some(idx) = state.turn_order.iter().position(|u| u == &next_uid) {
                        state.turn_index = idx;
                    }
                } else {
                    Self::finalize_game(state, &map);
                }
            }
            PlanetXStage::MeetingProposal => {
                if !state.meeting_ready_users.iter().any(|u| u == user_id) {
                    state.meeting_ready_users.push(user_id.to_string());
                }

                if state.meeting_ready_users.len() >= state.turn_order.len() {
                    state.game_stage = PlanetXStage::MeetingPublish;
                    state.meeting_published_users.clear();
                    state.turn_index = 0;
                } else {
                    state.advance_turn();
                }
            }
            PlanetXStage::MeetingPublish => {
                if !state.meeting_published_users.iter().any(|u| u == user_id) {
                    state.meeting_published_users.push(user_id.to_string());
                }

                if state.meeting_published_users.len() >= state.turn_order.len() {
                    state.game_stage = PlanetXStage::MeetingCheck;
                } else {
                    state.advance_turn();
                }
            }
            PlanetXStage::MeetingCheck => {
                return Err(game::GameError::Invalid(
                    "planetx_invalid_move_in_stage".into(),
                ));
            }
            PlanetXStage::GameEnd => {}
        }

        Ok(result)
    }

    fn resolve_meeting_check_transition(state: &mut PlanetXState, map: &Map) {
        Self::resolve_meeting_checks(state, map);
        for tokens in state.user_tokens.values_mut() {
            for token in tokens.iter_mut() {
                token.push_at_meeting(&state.revealed_sector_indexes);
            }
        }
        state.game_stage = PlanetXStage::UserMove;
        state.meeting_ready_users.clear();
        state.meeting_published_users.clear();
        state.advance_turn();
        state.recompute_visible_range();
    }

    fn op_allowed_in_stage(stage: &PlanetXStage, op: &Operation) -> bool {
        match stage {
            PlanetXStage::UserMove => matches!(
                op,
                Operation::Survey(_) | Operation::Target(_) | Operation::Research(_) | Operation::Locate(_)
            ),
            PlanetXStage::MeetingProposal => matches!(op, Operation::ReadyPublish(_)),
            PlanetXStage::MeetingPublish => matches!(op, Operation::DoPublish(_)),
            PlanetXStage::MeetingCheck => false,
            PlanetXStage::LastMove => matches!(op, Operation::Locate(_) | Operation::DoPublish(_)),
            PlanetXStage::GameEnd => false,
        }
    }

    fn operation_cost(op: &Operation, map_size: usize) -> usize {
        match op {
            Operation::Survey(s) => {
                let range_len = if s.start <= s.end {
                    s.end - s.start + 1
                } else {
                    map_size - s.start + s.end + 1
                };
                4usize.saturating_sub((range_len.saturating_sub(1)) / 3)
            }
            Operation::Target(_) => 4,
            Operation::Research(_) => 1,
            Operation::Locate(_) => 5,
            Operation::ReadyPublish(_) | Operation::DoPublish(_) => 0,
        }
    }

    fn is_meeting_triggered(state: &PlanetXState, previous_step: usize, op_cost: usize) -> bool {
        if op_cost == 0 {
            return false;
        }
        let max = state.map_type.sector_count();
        let meeting_points = state
            .map_type
            .meeting_points()
            .into_iter()
            .map(|(idx, _)| idx)
            .collect::<Vec<_>>();
        Self::crossed_points(previous_step, op_cost, max)
            .into_iter()
            .any(|p| meeting_points.contains(&p))
    }

    fn crossed_points(previous_step: usize, delta: usize, max: usize) -> Vec<usize> {
        if delta == 0 || max == 0 {
            return vec![];
        }
        (1..=delta)
            .map(|i| {
                let abs = previous_step + i;
                ((abs - 1) % max) + 1
            })
            .collect()
    }

    fn unlock_x_clues_on_pass(state: &mut PlanetXState, previous_step: usize, op_cost: usize) {
        if op_cost == 0 {
            return;
        }

        // Legacy behavior: X clues are unlocked only during the first lap.
        let max = state.map_type.sector_count();
        if previous_step >= max {
            return;
        }

        let mut newly_unlocked = Vec::new();
        for i in 1..=op_cost {
            let abs = previous_step + i;
            if abs > max {
                break;
            }
            let pos = ((abs - 1) % max) + 1;
            let x_point_index = state
                .map_type
                .xclue_points()
                .iter()
                .position(|(idx, _)| *idx == pos);
            let Some(x_idx) = x_point_index else {
                continue;
            };
            let Some(clue) = state.x_clues.get(x_idx).cloned() else {
                continue;
            };
            if state.revealed_x_clues.iter().any(|c| *c == clue.index) {
                continue;
            }
            newly_unlocked.push(clue);
        }

        if newly_unlocked.is_empty() {
            return;
        }

        for clue in newly_unlocked {
            state.revealed_x_clues.push(clue.index.clone());
            let op = Operation::Research(ResearchOperation {
                index: clue.index.clone(),
            });
            let result = OperationResult::Research(clue.clone());

            for uid in state.turn_order.clone() {
                state
                    .player_results
                    .entry(uid.clone())
                    .or_default()
                    .push(result.clone());
                if let Some(filter) = state.choice_filters.get_mut(&uid) {
                    filter.add_operation(op.clone(), result.clone());
                }
            }
        }
    }

    fn in_visible_range(start_index: usize, end_index: usize, index: usize, max: usize) -> bool {
        if start_index == 0 || end_index == 0 || index == 0 || max == 0 {
            return false;
        }
        if start_index > max || end_index > max || index > max {
            return false;
        }
        if start_index <= end_index {
            return index >= start_index && index <= end_index;
        }
        index >= start_index || index <= end_index
    }

    fn should_enter_last_move(result: &OperationResult) -> bool {
        matches!(result, OperationResult::Locate(true))
    }

    fn build_last_move_users(state: &PlanetXState, locator_user: &str) -> Vec<String> {
        let locator_step = state.player_steps.get(locator_user).copied().unwrap_or(0);
        let mut users = state
            .turn_order
            .iter()
            .filter(|u| u.as_str() != locator_user)
            .filter(|u| state.player_steps.get((*u).as_str()).copied().unwrap_or(0) < locator_step)
            .cloned()
            .collect::<Vec<_>>();
        users.sort_by(|a, b| {
            let sa = state.player_steps.get(a).copied().unwrap_or(0);
            let sb = state.player_steps.get(b).copied().unwrap_or(0);
            sa.cmp(&sb).then_with(|| {
                let ia = state.turn_order.iter().position(|u| u == a).unwrap_or(usize::MAX);
                let ib = state.turn_order.iter().position(|u| u == b).unwrap_or(usize::MAX);
                ia.cmp(&ib)
            })
        });
        users
    }

    fn finalize_game(state: &mut PlanetXState, map: &Map) {
        state.game_stage = PlanetXStage::GameEnd;
        state.meeting_ready_users.clear();
        state.meeting_published_users.clear();
        state.last_move_users.clear();

        for tokens in state.user_tokens.values_mut() {
            for token in tokens.iter_mut() {
                if token.reveal_in_the_end() && !map.meeting_check(token.secret.sector_index, &token.r#type)
                {
                    token.secret.meeting_index = 4;
                }
            }
        }

        let map_type = state.map_type.clone();
        let mut results = Vec::new();
        for user_id in &state.turn_order {
            let tokens = state.user_tokens.get(user_id);

            let comet = tokens
                .map(|v| {
                    v.iter()
                        .filter(|t| t.is_success_located(SectorType::Comet))
                        .count()
                })
                .unwrap_or(0);
            let asteroid = tokens
                .map(|v| {
                    v.iter()
                        .filter(|t| t.is_success_located(SectorType::Asteroid))
                        .count()
                })
                .unwrap_or(0);
            let dwarf_planet = tokens
                .map(|v| {
                    v.iter()
                        .filter(|t| t.is_success_located(SectorType::DwarfPlanet))
                        .count()
                })
                .unwrap_or(0);
            let nebula = tokens
                .map(|v| {
                    v.iter()
                        .filter(|t| t.is_success_located(SectorType::Nebula))
                        .count()
                })
                .unwrap_or(0);

            let mut first = 0;
            for sector_index in 1..=map_type.sector_count() {
                let mut sector_tokens = state
                    .user_tokens
                    .values()
                    .flat_map(|all_tokens| {
                        all_tokens.iter().filter(|t| {
                            t.secret.sector_index == sector_index && t.is_success_located_any()
                        })
                    })
                    .collect::<Vec<_>>();
                sector_tokens.sort_by(|a, b| a.secret.meeting_index.cmp(&b.secret.meeting_index));
                let Some(first_meeting_index) = sector_tokens.first().map(|t| t.secret.meeting_index) else {
                    continue;
                };
                if sector_tokens.iter().any(|t| {
                    t.secret.meeting_index == first_meeting_index && t.secret.user_id == *user_id
                }) {
                    first += 1;
                }
            }

            let step = state.player_steps.get(user_id).copied().unwrap_or(0);
            let x = state
                .player_results
                .get(user_id)
                .and_then(|v| v.last())
                .map_or(0, |r| match r {
                    OperationResult::Locate(true) => {
                        if state.terminator_step == step {
                            10
                        } else {
                            2 * state.terminator_step.saturating_sub(step)
                        }
                    }
                    _ => 0,
                });

            let sum = (match map_type {
                crate::map::MapType::Standard => dwarf_planet * 4,
                crate::map::MapType::Expert => dwarf_planet * 2,
            }) + asteroid * 2
                + comet * 3
                + nebula * 4
                + first
                + x;

            results.push(crate::model::UserResultSummary {
                id: user_id.clone(),
                name: user_id.clone(),
                sum,
                first,
                comet,
                asteroid,
                dwarf_planet,
                nebula,
                x,
                step,
            });
        }

        results.sort_by(|a, b| a.sum.cmp(&b.sum).then_with(|| a.first.cmp(&b.first)));
        results.reverse();
        state.game_result = Some(results);
    }

    fn resolve_meeting_checks(state: &mut PlanetXState, map: &Map) {
        let mut to_reveal = Vec::<usize>::new();

        // First pass: tokens whose meeting countdown reached 0 are checked directly.
        for tokens in state.user_tokens.values_mut() {
            for token in tokens.iter_mut() {
                if !token.any_ready_checked() {
                    continue;
                }
                let correct = map.meeting_check(token.secret.sector_index, &token.r#type);
                token.secret.r#type = Some(token.r#type.clone());
                if correct {
                    to_reveal.push(token.secret.sector_index);
                } else {
                    token.secret.meeting_index = 4;
                    let owner = token.secret.user_id.clone();
                    let step = state.player_steps.entry(owner).or_insert(0);
                    *step += 1;
                }
            }
        }

        for idx in to_reveal {
            if !state.revealed_sector_indexes.contains(&idx) {
                state.revealed_sector_indexes.push(idx);
            }
        }

        // Second pass: tokens on already revealed sectors are checked immediately.
        for tokens in state.user_tokens.values_mut() {
            for token in tokens.iter_mut() {
                if !(token.secret.r#type.is_none()
                    && token.placed
                    && state.revealed_sector_indexes.contains(&token.secret.sector_index))
                {
                    continue;
                }
                let correct = map.meeting_check(token.secret.sector_index, &token.r#type);
                token.secret.r#type = Some(token.r#type.clone());
                if !correct {
                    token.secret.meeting_index = 4;
                    let owner = token.secret.user_id.clone();
                    let step = state.player_steps.entry(owner).or_insert(0);
                    *step += 1;
                }
            }
        }
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
        s.user_tokens = s
            .turn_order
            .iter()
            .enumerate()
            .map(|(i, id)| (id.clone(), s.map_type.generate_tokens(id.clone(), i + 1)))
            .collect();
        s.revealed_sector_indexes.clear();
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
        let (research_clues, x_clues) = match clue_gen.generate_clues() {
            Ok(v) => v,
            Err(_) => {
                return ActionResult::Err(game::GameError::Internal(
                    "planetx_clue_generation_failed".into(),
                ));
            }
        };
        s.research_clues = research_clues;
        s.x_clues = x_clues;
        s.revealed_x_clues.clear();
        s.game_stage = PlanetXStage::UserMove;
        s.start_index = 1;
        s.end_index = s.map_type.sector_count() / 2;
        s.meeting_ready_users.clear();
        s.meeting_published_users.clear();
        s.last_move_users.clear();
        s.terminator_step = 0;
        s.game_result = None;
        s.recompute_visible_range();
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

                let mut meeting_check_snapshot: Option<PlanetXState> = None;
                if matches!(s.game_stage, PlanetXStage::MeetingCheck) {
                    meeting_check_snapshot = Some(s.clone());
                    let map = match Self::build_runtime_map(s) {
                        Ok(m) => m,
                        Err(e) => return ActionResult::Err(e),
                    };
                    Self::resolve_meeting_check_transition(s, &map);
                }

                s.seq += 1;
                s.last_actor = Some(action.user_id.clone());
                s.last_payload = Some(action.payload.clone());

                let mut broadcasts = vec![Outbound {
                    target: OutboundTarget::User(action.user_id.clone()),
                    payload: json!({
                        "type": "planetx_op_result",
                        "room": ctx.room_id,
                        "seq": s.seq,
                        "ok": true,
                        "op": op,
                        "result": op_result_json,
                    }),
                }];

                if let Some(snapshot) = meeting_check_snapshot {
                    broadcasts.push(Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "game": "planetx",
                            "room": ctx.room_id,
                            "event": "action_applied",
                            "state": snapshot,
                        }),
                    });
                    broadcasts.push(Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "game": "planetx",
                            "room": ctx.room_id,
                            "event": "meeting_check_entered",
                            "state": snapshot,
                        }),
                    });
                    broadcasts.push(Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "game": "planetx",
                            "room": ctx.room_id,
                            "event": "meeting_check_resolved",
                            "state": s,
                        }),
                    });
                } else {
                    broadcasts.push(Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "game": "planetx",
                            "room": ctx.room_id,
                            "event": "action_applied",
                            "state": s,
                        }),
                    });
                }

                ActionResult::Ok {
                    events: vec![],
                    broadcasts,
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map::{Clue, ClueConnection, ClueEnum, MapType, SectorType};
    use crate::operation::{
        DoPublishOperation, LocateOperation, Operation, ReadyPublishOperation, SurveyOperation,
        TargetOperation,
    };

    fn standard_test_map() -> Vec<SectorType> {
        vec![
            SectorType::Comet,
            SectorType::Comet,
            SectorType::Comet,
            SectorType::X,
            SectorType::Asteroid,
            SectorType::Space,
            SectorType::Space,
            SectorType::Space,
            SectorType::Space,
            SectorType::Space,
            SectorType::Space,
            SectorType::Space,
        ]
    }

    fn base_state(players: &[&str]) -> PlanetXState {
        let mut s = PlanetXState::new();
        s.started = true;
        s.map_type = MapType::Standard;
        s.map_sectors = standard_test_map();
        s.turn_order = players.iter().map(|u| (*u).to_string()).collect();
        s.players = s.turn_order.clone();
        s.turn_index = 0;
        s.start_index = 1;
        s.end_index = s.map_type.sector_count();
        s
    }

    #[test]
    fn meeting_flow_proposal_to_publish_to_user_move() {
        let mut s = base_state(&["alice", "bob"]);
        s.game_stage = PlanetXStage::MeetingProposal;
        s.user_tokens
            .insert("alice".into(), s.map_type.generate_tokens("alice".into(), 1));
        s.user_tokens
            .insert("bob".into(), s.map_type.generate_tokens("bob".into(), 2));

        let r1 = PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::ReadyPublish(ReadyPublishOperation {
                sectors: vec![SectorType::Comet],
            }),
        )
        .expect("alice ready publish should succeed");
        assert!(matches!(r1, OperationResult::ReadyPublish(1)));
        assert_eq!(s.game_stage, PlanetXStage::MeetingProposal);
        assert_eq!(s.turn_order[s.turn_index], "bob");

        let r2 = PlanetXGame::apply_planetx_operation(
            &mut s,
            "bob",
            &Operation::ReadyPublish(ReadyPublishOperation {
                sectors: vec![SectorType::Comet],
            }),
        )
        .expect("bob ready publish should succeed");
        assert!(matches!(r2, OperationResult::ReadyPublish(1)));
        assert_eq!(s.game_stage, PlanetXStage::MeetingPublish);
        assert_eq!(s.turn_order[s.turn_index], "alice");

        let r3 = PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::DoPublish(DoPublishOperation {
                index: 1,
                sector_type: SectorType::Comet,
            }),
        )
        .expect("alice do publish should succeed");
        assert!(matches!(r3, OperationResult::DoPublish((1, SectorType::Comet))));
        assert_eq!(s.game_stage, PlanetXStage::MeetingPublish);
        assert_eq!(s.turn_order[s.turn_index], "bob");

        let r4 = PlanetXGame::apply_planetx_operation(
            &mut s,
            "bob",
            &Operation::DoPublish(DoPublishOperation {
                index: 2,
                sector_type: SectorType::Comet,
            }),
        )
        .expect("bob do publish should succeed");
        assert!(matches!(r4, OperationResult::DoPublish((2, SectorType::Comet))));
        assert_eq!(s.game_stage, PlanetXStage::MeetingCheck);

        let map = PlanetXGame::build_runtime_map(&s).expect("map should be available");
        PlanetXGame::resolve_meeting_check_transition(&mut s, &map);
        assert_eq!(s.game_stage, PlanetXStage::UserMove);
        assert!(s.meeting_ready_users.is_empty());
        assert!(s.meeting_published_users.is_empty());
    }

    #[test]
    fn locate_success_enters_last_move_and_finishes_game_end() {
        let mut s = base_state(&["alice", "bob", "carol"]);
        s.player_steps.insert("alice".into(), 7);
        s.player_steps.insert("bob".into(), 5);
        s.player_steps.insert("carol".into(), 9);
        s.turn_index = 2;

        let locate_ok = Operation::Locate(LocateOperation {
            index: 4,
            pre_sector_type: SectorType::Comet,
            next_sector_type: SectorType::Asteroid,
        });
        let locate_bad = Operation::Locate(LocateOperation {
            index: 4,
            pre_sector_type: SectorType::Asteroid,
            next_sector_type: SectorType::Comet,
        });

        let r1 = PlanetXGame::apply_planetx_operation(&mut s, "carol", &locate_ok)
            .expect("carol locate should succeed");
        assert!(matches!(r1, OperationResult::Locate(true)));
        assert_eq!(s.game_stage, PlanetXStage::LastMove);
        assert_eq!(s.last_move_users, vec!["bob".to_string(), "alice".to_string()]);
        assert_eq!(s.turn_order[s.turn_index], "bob");

        PlanetXGame::apply_planetx_operation(&mut s, "bob", &locate_bad)
            .expect("bob last move should succeed");
        assert_eq!(s.game_stage, PlanetXStage::LastMove);
        assert_eq!(s.last_move_users, vec!["alice".to_string()]);
        assert_eq!(s.turn_order[s.turn_index], "alice");

        PlanetXGame::apply_planetx_operation(&mut s, "alice", &locate_bad)
            .expect("alice last move should succeed");
        assert_eq!(s.game_stage, PlanetXStage::GameEnd);
        assert!(s.last_move_users.is_empty());
        assert!(s.game_result.is_some());

        let blocked = PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::Target(TargetOperation { index: 1 }),
        );
        assert!(matches!(
            blocked,
            Err(game::GameError::Invalid(msg)) if msg == "planetx_invalid_move_in_stage"
        ));
    }

    #[test]
    fn crossing_meeting_point_triggers_meeting() {
        let mut s = base_state(&["alice", "bob"]);
        s.player_steps.insert("alice".into(), 2);
        s.player_steps.insert("bob".into(), 0);

        PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::Target(TargetOperation { index: 1 }),
        )
        .expect("target should succeed");

        assert_eq!(s.game_stage, PlanetXStage::MeetingProposal);
        assert!(s.meeting_ready_users.is_empty());
        assert!(s.meeting_published_users.is_empty());
    }

    #[test]
    fn crossing_x_point_unlocks_x_clue_for_all_players() {
        let mut s = base_state(&["alice", "bob"]);
        s.x_clues = vec![Clue {
            index: ClueEnum::X1,
            subject: SectorType::X,
            object: SectorType::Comet,
            conn: ClueConnection::NotAdjacent,
        }];
        s.player_steps.insert("alice".into(), 8);
        s.player_steps.insert("bob".into(), 1);

        PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::Target(TargetOperation { index: 1 }),
        )
        .expect("target should succeed");

        assert_eq!(s.revealed_x_clues, vec![ClueEnum::X1]);
        let alice_results = s.player_results.get("alice").cloned().unwrap_or_default();
        let bob_results = s.player_results.get("bob").cloned().unwrap_or_default();
        assert!(alice_results
            .iter()
            .any(|r| matches!(r, OperationResult::Research(Clue { index: ClueEnum::X1, .. }))));
        assert!(bob_results
            .iter()
            .any(|r| matches!(r, OperationResult::Research(Clue { index: ClueEnum::X1, .. }))));
    }

    #[test]
    fn x_clue_unlock_does_not_block_manual_research() {
        let mut s = base_state(&["alice", "bob"]);
        s.x_clues = vec![Clue {
            index: ClueEnum::X1,
            subject: SectorType::X,
            object: SectorType::Comet,
            conn: ClueConnection::NotAdjacent,
        }];
        s.research_clues = vec![Clue {
            index: ClueEnum::A,
            subject: SectorType::Comet,
            object: SectorType::Asteroid,
            conn: ClueConnection::NotAdjacent,
        }];
        s.player_steps.insert("alice".into(), 9);
        s.player_steps.insert("bob".into(), 1);

        PlanetXGame::apply_planetx_operation(
            &mut s,
            "alice",
            &Operation::Survey(SurveyOperation {
                sector_type: SectorType::Space,
                start: 1,
                end: 12,
            }),
        )
        .expect("survey should succeed and unlock x clue");

        let res = PlanetXGame::apply_planetx_operation(
            &mut s,
            "bob",
            &Operation::Research(ResearchOperation { index: ClueEnum::A }),
        )
        .expect("manual research should still be allowed after x clue unlock");

        assert!(matches!(res, OperationResult::Research(Clue { index: ClueEnum::A, .. })));
    }
}