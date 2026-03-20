use async_trait::async_trait;
use serde_json::Value;
use serde_json::json;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::OnceLock;

use boardgames_server::game::{
    self, Action, ActionCtx, ActionResult, Game, GameDescriptor, GameState, Outbound,
    OutboundTarget,
};
use crate::{
    AcquireGame, AcquireState, BOARD_MAX_COL, BOARD_MAX_ROW, COMPANY_IDS, CompanyState,
    FinalStanding, FoundingContext, MergeContext, MergeSettlement, PlacementKind,
};

impl AcquireState {
    fn new() -> Self {
        let mut stock_pool = HashMap::new();
        for id in COMPANY_IDS {
            stock_pool.insert(id.to_string(), 25);
        }

        Self {
            tiles: HashSet::new(),
            moves: vec![],
            players: HashMap::new(),
            shares: HashMap::new(),
            stock_pool,
            tile_bag: Self::build_tile_bag(),
            player_tiles: HashMap::new(),
            independent_tiles: HashSet::new(),
            tile_company: HashMap::new(),
            companies: HashMap::new(),
            merge_context: None,
            merge_settlement: None,
            founding_context: None,
            game_over: false,
            final_standings: vec![],
            turn_order: vec![],
            current_turn: 0,
            phase: "place".to_string(),
            turn_no: 1,
        }
    }

    fn build_tile_bag() -> VecDeque<String> {
        let mut bag = VecDeque::new();
        for col in 1..=BOARD_MAX_COL {
            for row in 1..=BOARD_MAX_ROW {
                bag.push_back(Self::encode_pos(col, row));
            }
        }
        bag
    }

    fn tile_in_any_hand(&self, pos: &str) -> bool {
        self.player_tiles.values().any(|hand| hand.contains(pos))
    }

    fn draw_tile_for_user(&mut self, user: &str) -> Option<String> {
        while let Some(pos) = self.tile_bag.pop_front() {
            if self.tiles.contains(&pos) || self.tile_in_any_hand(&pos) {
                continue;
            }
            self.player_tiles
                .entry(user.to_string())
                .or_default()
                .insert(pos.clone());
            return Some(pos);
        }
        None
    }

    fn refill_player_tiles(&mut self, user: &str, target: usize) {
        let mut hand_size = self
            .player_tiles
            .get(user)
            .map(HashSet::len)
            .unwrap_or(0);
        while hand_size < target {
            if self.draw_tile_for_user(user).is_none() {
                break;
            }
            hand_size += 1;
        }
    }

    pub(crate) fn current_player(&self) -> Option<&str> {
        self.turn_order
            .get(self.current_turn)
            .map(std::string::String::as_str)
    }

    fn can_start(&self) -> bool {
        self.turn_order.len() >= 2
    }

    fn advance_turn(&mut self) {
        if self.turn_order.is_empty() {
            self.current_turn = 0;
        } else {
            self.current_turn = (self.current_turn + 1) % self.turn_order.len();
        }
        self.turn_no += 1;
        self.phase = "place".to_string();
    }

    pub(crate) fn first_inactive_company(&self) -> Option<String> {
        for id in COMPANY_IDS {
            if !self.companies.contains_key(id) {
                return Some(id.to_string());
            }
        }
        None
    }

    fn is_known_company(company_id: &str) -> bool {
        COMPANY_IDS.iter().any(|c| c == &company_id)
    }

    fn share_mut(&mut self, user: &str, company: &str) -> &mut i64 {
        self.shares
            .entry(user.to_string())
            .or_default()
            .entry(company.to_string())
            .or_insert(0)
    }

    fn parse_pos(pos: &str) -> Option<(i32, i32)> {
        let p = pos.trim();
        if p.len() < 2 {
            return None;
        }
        let (col_str, row_str) = p.split_at(p.len() - 1);
        if col_str.is_empty() || !col_str.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let row_ch = row_str.chars().next()?.to_ascii_uppercase();
        if !row_ch.is_ascii_alphabetic() {
            return None;
        }
        let col: i32 = col_str.parse().ok()?;
        let row = (row_ch as u8).checked_sub(b'A')? as i32 + 1;
        if !(1..=BOARD_MAX_COL).contains(&col) || !(1..=BOARD_MAX_ROW).contains(&row) {
            return None;
        }
        Some((col, row))
    }

    fn encode_pos(col: i32, row: i32) -> String {
        let row_ch = ((row - 1) as u8 + b'A') as char;
        format!("{}{}", col, row_ch)
    }

    fn neighbors(pos: &str) -> Vec<String> {
        let Some((col, row)) = Self::parse_pos(pos) else {
            return vec![];
        };
        let deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)];
        let mut out = Vec::with_capacity(4);
        for (dc, dr) in deltas {
            let nc = col + dc;
            let nr = row + dr;
            if (1..=BOARD_MAX_COL).contains(&nc) && (1..=BOARD_MAX_ROW).contains(&nr) {
                out.push(Self::encode_pos(nc, nr));
            }
        }
        out
    }

    fn classify_placement(&self, pos: &str) -> PlacementKind {
        let mut company_ids = HashSet::new();
        let mut has_independent = false;
        let mut has_adjacent = false;

        for n in Self::neighbors(pos) {
            if self.tiles.contains(&n) {
                has_adjacent = true;
            }
            if let Some(cid) = self.tile_company.get(&n) {
                company_ids.insert(cid.clone());
            } else if self.independent_tiles.contains(&n) {
                has_independent = true;
            }
        }

        if company_ids.len() > 1 {
            return PlacementKind::Merge(company_ids.into_iter().collect());
        }
        if company_ids.len() == 1 {
            return PlacementKind::Expand(company_ids.into_iter().next().unwrap_or_default());
        }
        if has_independent {
            return PlacementKind::FoundCandidate;
        }
        if !has_adjacent {
            return PlacementKind::Isolated;
        }
        PlacementKind::Isolated
    }

    fn has_founding_opportunity_on_board(&self) -> bool {
        for col in 1..=BOARD_MAX_COL {
            for row in 1..=BOARD_MAX_ROW {
                let pos = Self::encode_pos(col, row);
                if self.tiles.contains(&pos) {
                    continue;
                }
                if matches!(self.classify_placement(&pos), PlacementKind::FoundCandidate) {
                    return true;
                }
            }
        }
        false
    }

    fn consume_connected_independent_component(&mut self, root_pos: &str) -> HashSet<String> {
        let mut component = HashSet::new();
        let mut q = VecDeque::new();
        q.push_back(root_pos.to_string());

        while let Some(cur) = q.pop_front() {
            if component.contains(&cur) {
                continue;
            }
            component.insert(cur.clone());
            for n in Self::neighbors(&cur) {
                if self.independent_tiles.contains(&n) && !component.contains(&n) {
                    q.push_back(n);
                }
            }
        }

        for pos in &component {
            self.independent_tiles.remove(pos);
        }
        component
    }

    fn refresh_company_safety(company: &mut CompanyState) {
        company.safe = company.tiles.len() >= 11;
    }

    fn company_size(&self, company_id: &str) -> usize {
        self.companies
            .get(company_id)
            .map(|c| c.tiles.len())
            .unwrap_or(0)
    }

    fn company_tier(company_id: &str) -> i64 {
        match company_id {
            "Worldwide" | "Sackson" => 0,
            "American" | "Festival" | "Imperial" => 1,
            "Continental" | "Tower" => 2,
            _ => 0,
        }
    }

    fn share_price_for_size(company_id: &str, size: usize) -> i64 {
        if size < 2 {
            return 0;
        }
        let base = match size {
            2 => 200,
            3 => 300,
            4 => 400,
            5 => 500,
            6..=10 => 600,
            11..=20 => 700,
            21..=30 => 800,
            31..=40 => 900,
            _ => 1000,
        };
        base + Self::company_tier(company_id) * 100
    }

    fn company_share_price(&self, company_id: &str) -> i64 {
        let size = self.company_size(company_id);
        Self::share_price_for_size(company_id, size)
    }

    fn allowed_merge_survivors(&self, candidates: &[String]) -> anyhow::Result<Vec<String>> {
        let safe_companies: Vec<String> = candidates
            .iter()
            .filter_map(|cid| {
                self.companies
                    .get(cid)
                    .and_then(|c| if c.safe { Some(cid.clone()) } else { None })
            })
            .collect();

        if safe_companies.len() > 1 {
            return Err(anyhow::anyhow!("cannot_merge_multiple_safe_companies"));
        }
        if safe_companies.len() == 1 {
            return Ok(safe_companies);
        }

        let mut best = 0usize;
        for cid in candidates {
            best = best.max(self.company_size(cid));
        }
        let out: Vec<String> = candidates
            .iter()
            .filter_map(|cid| {
                if self.company_size(cid) == best {
                    Some(cid.clone())
                } else {
                    None
                }
            })
            .collect();

        if out.is_empty() {
            return Err(anyhow::anyhow!("no_merge_survivor_candidates"));
        }

        Ok(out)
    }

    fn share_count(&self, user: &str, company: &str) -> i64 {
        self.shares
            .get(user)
            .and_then(|m| m.get(company))
            .copied()
            .unwrap_or(0)
    }

    pub(crate) fn set_share_count(&mut self, user: &str, company: &str, count: i64) {
        let c = count.max(0);
        self.shares
            .entry(user.to_string())
            .or_default()
            .insert(company.to_string(), c);
    }

    fn payout_merge_bonus_for_company(&mut self, loser_company: &str) {
        let price = self.company_share_price(loser_company);
        if price <= 0 {
            return;
        }

        let mut holders: Vec<(String, i64)> = self
            .players
            .keys()
            .map(|u| (u.clone(), self.share_count(u, loser_company)))
            .filter(|(_, n)| *n > 0)
            .collect();
        if holders.is_empty() {
            return;
        }

        holders.sort_by(|a, b| match b.1.cmp(&a.1) {
            Ordering::Equal => a.0.cmp(&b.0),
            x => x,
        });

        let first_shares = holders[0].1;
        let first_group: Vec<String> = holders
            .iter()
            .filter_map(|(u, n)| if *n == first_shares { Some(u.clone()) } else { None })
            .collect();

        let first_bonus = 10 * price;
        let second_bonus = 5 * price;

        if first_group.len() >= 2 {
            let pool = first_bonus + second_bonus;
            let each = pool / first_group.len() as i64;
            for user in first_group {
                *self.players.entry(user).or_insert(0) += each;
            }
            return;
        }

        let first_user = holders[0].0.clone();
        *self.players.entry(first_user).or_insert(0) += first_bonus;

        let second_shares = holders.iter().find(|(_, n)| *n < first_shares).map(|(_, n)| *n);
        let Some(second_shares) = second_shares else {
            return;
        };
        let second_group: Vec<String> = holders
            .iter()
            .filter_map(|(u, n)| if *n == second_shares { Some(u.clone()) } else { None })
            .collect();
        if second_group.is_empty() {
            return;
        }

        let each = second_bonus / second_group.len() as i64;
        for user in second_group {
            *self.players.entry(user).or_insert(0) += each;
        }
    }

    fn build_merge_settlement(&self, placed_pos: &str, candidates: &[String], survivor: &str) -> MergeSettlement {
        let losers: Vec<String> = candidates
            .iter()
            .filter_map(|cid| if cid != survivor { Some(cid.clone()) } else { None })
            .collect();

        let mut pending: HashMap<String, HashSet<String>> = HashMap::new();
        for user in self.players.keys() {
            let mut needs = HashSet::new();
            for loser in &losers {
                if self.share_count(user, loser) > 0 {
                    needs.insert(loser.clone());
                }
            }
            if !needs.is_empty() {
                pending.insert(user.clone(), needs);
            }
        }

        MergeSettlement {
            placed_pos: placed_pos.to_string(),
            candidates: candidates.to_vec(),
            survivor: survivor.to_string(),
            losers,
            pending,
        }
    }

    fn merge_settlement_complete(&self) -> bool {
        self.merge_settlement
            .as_ref()
            .map(|m| m.pending.values().all(HashSet::is_empty))
            .unwrap_or(true)
    }

    fn can_declare_end(&self) -> bool {
        let any_41 = self
            .companies
            .values()
            .any(|c| c.tiles.len() >= 41);
        if any_41 {
            return true;
        }

        let has_active = !self.companies.is_empty();
        let all_safe = self.companies.values().all(|c| c.safe);
        let no_new_company_possible = self.first_inactive_company().is_none()
            || !self.has_founding_opportunity_on_board();
        has_active && all_safe && no_new_company_possible
    }

    fn settle_endgame(&mut self) {
        let company_ids: Vec<String> = self.companies.keys().cloned().collect();
        for cid in &company_ids {
            self.payout_merge_bonus_for_company(cid);
        }

        let users: Vec<String> = self.players.keys().cloned().collect();
        for uid in &users {
            let holdings = self.shares.get(uid).cloned().unwrap_or_default();
            let mut liquidation = 0i64;
            for (cid, qty) in holdings {
                if qty <= 0 {
                    continue;
                }
                if self.companies.contains_key(&cid) {
                    liquidation += qty * self.company_share_price(&cid);
                }
                self.set_share_count(uid, &cid, 0);
            }
            *self.players.entry(uid.clone()).or_insert(0) += liquidation;
        }

        let mut rank: Vec<FinalStanding> = self
            .players
            .iter()
            .map(|(u, c)| FinalStanding {
                user_id: u.clone(),
                cash: *c,
            })
            .collect();
        rank.sort_by(|a, b| match b.cash.cmp(&a.cash) {
            Ordering::Equal => a.user_id.cmp(&b.user_id),
            x => x,
        });

        self.final_standings = rank;
        self.game_over = true;
        self.phase = "game_over".to_string();
    }

    fn apply_merge(&mut self, survivor: &str, candidates: &[String], placed_pos: &str) -> anyhow::Result<()> {
        if !self.companies.contains_key(survivor) {
            return Err(anyhow::anyhow!("survivor_not_found"));
        }

        let mut absorbed_tiles: Vec<String> = Vec::new();
        for cid in candidates {
            if cid == survivor {
                continue;
            }
            if let Some(company) = self.companies.remove(cid) {
                absorbed_tiles.extend(company.tiles.into_iter());
            }
        }

        if let Some(survivor_company) = self.companies.get_mut(survivor) {
            for t in absorbed_tiles {
                survivor_company.tiles.insert(t);
            }
            survivor_company.tiles.insert(placed_pos.to_string());
            AcquireState::refresh_company_safety(survivor_company);
        }

        for (pos, cid) in &mut self.tile_company {
            if candidates.iter().any(|c| c == cid) {
                *cid = survivor.to_string();
            }
            if pos == placed_pos {
                *cid = survivor.to_string();
            }
        }
        self.tile_company
            .entry(placed_pos.to_string())
            .or_insert_with(|| survivor.to_string());

        // Any independent regions adjacent to the merge tile are absorbed by the survivor.
        let mut absorbed_independent = HashSet::new();
        for n in Self::neighbors(placed_pos) {
            if self.independent_tiles.contains(&n) {
                let comp = self.consume_connected_independent_component(&n);
                absorbed_independent.extend(comp);
            }
        }
        if let Some(survivor_company) = self.companies.get_mut(survivor) {
            for t in absorbed_independent {
                self.tile_company.insert(t.clone(), survivor.to_string());
                survivor_company.tiles.insert(t);
            }
            AcquireState::refresh_company_safety(survivor_company);
        }

        Ok(())
    }

    pub fn snapshot_state(&self) -> Value {
        let mut v = serde_json::to_value(self).unwrap_or_else(|_| json!({}));
        if let Some(obj) = v.as_object_mut() {
            obj.insert("current_player".to_string(), json!(self.current_player()));
        }
        v
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
        let restored: AcquireState = serde_json::from_value(v)?;
        *self = restored;
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
        Box::new(AcquireState::new())
    }

    async fn on_join(
        &self,
        _ctx: &ActionCtx,
        state: &mut dyn GameState,
        user: String,
    ) -> ActionResult {
        let any = state as &mut dyn std::any::Any;
        let s = match any.downcast_mut::<AcquireState>() {
            Some(s) => s,
            None => {
                return ActionResult::Err(game::GameError::Internal("state type mismatch".into()));
            }
        };

        if !s.players.contains_key(&user) {
            s.players.insert(user.clone(), 6000);
            s.shares.insert(user.clone(), HashMap::new());
            s.player_tiles.insert(user.clone(), HashSet::new());
            s.refill_player_tiles(&user, 6);
            s.turn_order.push(user.clone());
        }

        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![Outbound {
                target: OutboundTarget::All,
                payload: json!({"type":"state","state": s.snapshot_state(), "room": _ctx.room_id}),
            }],
        }
    }

    async fn handle_action(
        &self,
        _ctx: &ActionCtx,
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

        if !s.players.contains_key(&action.user_id) {
            s.players.insert(action.user_id.clone(), 6000);
            s.shares
                .entry(action.user_id.clone())
                .or_insert_with(HashMap::new);
            s.player_tiles
                .entry(action.user_id.clone())
                .or_insert_with(HashSet::new);
            s.refill_player_tiles(&action.user_id, 6);
            if !s.turn_order.iter().any(|u| u == &action.user_id) {
                s.turn_order.push(action.user_id.clone());
            }
        }

        if !s.can_start() {
            return ActionResult::Err(game::GameError::Invalid(
                "not_enough_players_min_2".into(),
            ));
        }
        if s.game_over {
            return ActionResult::Err(game::GameError::Invalid("game_already_over".into()));
        }

        let current_player = match s.current_player() {
            Some(p) => p.to_string(),
            None => {
                return ActionResult::Err(game::GameError::State(
                    "missing_current_player".into(),
                ));
            }
        };

        // action schema examples:
        // {"type":"place","pos":"1A"}
        // {"type":"buy","shares":1}
        // {"type":"choose_company","company":"Worldwide"}
        // {"type":"resolve_merge","survivor":"Worldwide"}
        let ty = action
            .payload
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if ty != "merge_stock_decision" && action.user_id != current_player {
            return ActionResult::Err(game::GameError::Invalid(
                "not_your_turn".into(),
            ));
        }

        match ty {
            "place" => {
                if s.phase != "place" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_place".into(),
                    ));
                }

                if let Some(pos) = action.payload.get("pos").and_then(|v| v.as_str()) {
                    if AcquireState::parse_pos(pos).is_none() {
                        return ActionResult::Err(game::GameError::Invalid(
                            "invalid_position".into(),
                        ));
                    }
                    let in_hand = s
                        .player_tiles
                        .get(&action.user_id)
                        .map(|h| h.contains(pos))
                        .unwrap_or(false);
                    if !in_hand {
                        return ActionResult::Err(game::GameError::Invalid(
                            "tile_not_in_hand".into(),
                        ));
                    }
                    // naive placement: reject if already placed
                    if s.tiles.contains(pos) {
                        return ActionResult::Err(game::GameError::Invalid(
                            "tile already placed".into(),
                        ));
                    }

                    let placement = s.classify_placement(pos);

                    s.tiles.insert(pos.to_string());
                    if let Some(hand) = s.player_tiles.get_mut(&action.user_id) {
                        hand.remove(pos);
                    }
                    s.refill_player_tiles(&action.user_id, 6);
                    s.moves.push((action.user_id.clone(), pos.to_string()));

                    let mut placement_label = "isolated".to_string();
                    match &placement {
                        PlacementKind::Isolated => {
                            s.independent_tiles.insert(pos.to_string());
                        }
                        PlacementKind::Expand(company_id) => {
                            s.tile_company.insert(pos.to_string(), company_id.clone());
                            let mut absorbed_independent = HashSet::new();
                            for n in AcquireState::neighbors(pos) {
                                if s.independent_tiles.contains(&n) {
                                    let comp = s.consume_connected_independent_component(&n);
                                    absorbed_independent.extend(comp);
                                }
                            }
                            if let Some(company) = s.companies.get_mut(company_id) {
                                company.tiles.insert(pos.to_string());
                                for t in absorbed_independent {
                                    s.tile_company.insert(t.clone(), company_id.clone());
                                    company.tiles.insert(t);
                                }
                                AcquireState::refresh_company_safety(company);
                            }
                            placement_label = format!("expand:{}", company_id);
                        }
                        PlacementKind::FoundCandidate => {
                            let Some(_any_company) = s.first_inactive_company() else {
                                return ActionResult::Err(game::GameError::State(
                                    "no_company_available_to_found".into(),
                                ));
                            };

                            let connected = s.consume_connected_independent_component(pos);
                            let mut company_tiles = connected;
                            company_tiles.insert(pos.to_string());
                            s.founding_context = Some(FoundingContext {
                                tiles: company_tiles.into_iter().collect(),
                            });
                            placement_label = "found_pending".to_string();
                        }
                        PlacementKind::Merge(_) => {}
                    }

                    let mut event = "place_ok".to_string();
                    if let PlacementKind::Merge(merge_targets) = placement {
                        let allowed = match s.allowed_merge_survivors(&merge_targets) {
                            Ok(v) => v,
                            Err(e) => {
                                return ActionResult::Err(game::GameError::Invalid(e.to_string()));
                            }
                        };

                        if allowed.len() == 1 {
                            let survivor = allowed[0].clone();
                            for loser in merge_targets.iter().filter(|cid| *cid != &survivor) {
                                s.payout_merge_bonus_for_company(loser);
                            }
                            s.merge_settlement = Some(
                                s.build_merge_settlement(pos, &merge_targets, &survivor),
                            );
                            if s.merge_settlement_complete() {
                                if let Err(e) = s.apply_merge(&survivor, &merge_targets, pos) {
                                    return ActionResult::Err(game::GameError::State(e.to_string()));
                                }
                                s.merge_settlement = None;
                                s.phase = "buy".to_string();
                                placement_label = format!("merge:{}", survivor);
                            } else {
                                s.phase = "merge_stock_decision".to_string();
                                placement_label = format!("merge_pending_stock:{}", survivor);
                                event = "merge_stock_decision_required".to_string();
                            }
                        } else {
                            s.merge_context = Some(MergeContext {
                                placed_pos: pos.to_string(),
                                candidates: merge_targets.clone(),
                                allowed_survivors: allowed,
                            });
                            placement_label = "merge_pending".to_string();
                            s.phase = "resolve_merge".to_string();
                            event = "merge_pending".to_string();
                        }
                    } else if s.founding_context.is_some() {
                        s.phase = "choose_company".to_string();
                        event = "choose_company_required".to_string();
                    } else {
                        s.phase = "buy".to_string();
                    }

                    // broadcast updated state to room
                    let payload = json!({
                        "type":"state",
                        "state": s.snapshot_state(),
                        "by": action.user_id,
                        "event": event,
                        "placement": placement_label
                    });
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
                if s.phase != "buy" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_buy".into(),
                    ));
                }

                // minimal buy: 0..=3 shares, flat 100/share
                let shares = action
                    .payload
                    .get("shares")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                if !(0..=3).contains(&shares) {
                    return ActionResult::Err(game::GameError::Invalid("invalid shares".into()));
                }

                let company = action
                    .payload
                    .get("company")
                    .and_then(|v| v.as_str())
                    .map(ToString::to_string);

                if shares > 0 {
                    let Some(cid) = company.as_ref() else {
                        return ActionResult::Err(game::GameError::Invalid(
                            "missing_company_for_buy".into(),
                        ));
                    };
                    if !s.companies.contains_key(cid) {
                        return ActionResult::Err(game::GameError::Invalid(
                            "company_not_active".into(),
                        ));
                    }
                    if let Some(pool) = s.stock_pool.get(cid)
                        && *pool < shares
                    {
                        return ActionResult::Err(game::GameError::Invalid(
                            "not_enough_stock_pool".into(),
                        ));
                    }
                }

                let unit_price = if shares > 0 {
                    let cid = company.as_ref().expect("checked above when shares > 0");
                    s.company_share_price(cid)
                } else {
                    0
                };
                if shares > 0 && unit_price <= 0 {
                    return ActionResult::Err(game::GameError::Invalid("company_not_tradeable".into()));
                }

                let player_cash = s.players.entry(action.user_id.clone()).or_insert(6000);
                let cost = shares * unit_price;
                if *player_cash < cost {
                    return ActionResult::Err(game::GameError::Invalid("not_enough_cash".into()));
                }
                *player_cash -= cost;
                let cash_after = *player_cash;

                if shares > 0 {
                    let cid = company.as_ref().expect("checked above when shares > 0");
                    if let Some(pool) = s.stock_pool.get_mut(cid) {
                        *pool -= shares;
                    }
                    *s.share_mut(&action.user_id, cid) += shares;
                }

                let holding_after = s
                    .shares
                    .get(&action.user_id)
                    .and_then(|m| company.as_ref().and_then(|cid| m.get(cid)))
                    .copied()
                    .unwrap_or(0);

                s.advance_turn();

                let out_self = Outbound {
                    target: OutboundTarget::User(action.user_id.clone()),
                    payload: json!({
                        "type":"buy_ok",
                        "user": action.user_id,
                        "company": company,
                        "unit_price": unit_price,
                        "shares": shares,
                        "holding": holding_after,
                        "cash": cash_after
                    }),
                };

                let out_state = Outbound {
                    target: OutboundTarget::All,
                    payload: json!({
                        "type":"state",
                        "state": s.snapshot_state(),
                        "event": "turn_advanced"
                    }),
                };

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![out_self, out_state],
                }
            }
            "choose_company" => {
                if s.phase != "choose_company" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_choose_company".into(),
                    ));
                }

                let company_id = action
                    .payload
                    .get("company")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                if company_id.is_empty() {
                    return ActionResult::Err(game::GameError::Invalid("missing_company".into()));
                }
                if !AcquireState::is_known_company(&company_id) {
                    return ActionResult::Err(game::GameError::Invalid("unknown_company".into()));
                }
                if s.companies.contains_key(&company_id) {
                    return ActionResult::Err(game::GameError::Invalid(
                        "company_already_active".into(),
                    ));
                }

                let founding = match s.founding_context.clone() {
                    Some(v) => v,
                    None => {
                        return ActionResult::Err(game::GameError::State(
                            "missing_founding_context".into(),
                        ));
                    }
                };

                let mut tile_set = HashSet::new();
                for t in founding.tiles {
                    tile_set.insert(t.clone());
                    s.tile_company.insert(t, company_id.clone());
                }

                let mut company = CompanyState {
                    id: company_id.clone(),
                    tiles: tile_set,
                    safe: false,
                };
                AcquireState::refresh_company_safety(&mut company);
                s.companies.insert(company_id.clone(), company);

                if let Some(pool) = s.stock_pool.get_mut(&company_id)
                    && *pool > 0
                {
                    *pool -= 1;
                    *s.share_mut(&action.user_id, &company_id) += 1;
                }

                s.founding_context = None;
                s.phase = "buy".to_string();

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type":"state",
                            "state": s.snapshot_state(),
                            "event":"company_founded",
                            "company": company_id,
                            "by": action.user_id,
                        }),
                    }],
                }
            }
            "resolve_merge" => {
                if s.phase != "resolve_merge" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_resolve_merge".into(),
                    ));
                }

                let ctx = match s.merge_context.clone() {
                    Some(v) => v,
                    None => {
                        return ActionResult::Err(game::GameError::State(
                            "missing_merge_context".into(),
                        ));
                    }
                };

                let survivor = action
                    .payload
                    .get("survivor")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                if survivor.is_empty() {
                    return ActionResult::Err(game::GameError::Invalid(
                        "missing_survivor".into(),
                    ));
                }
                if !ctx.allowed_survivors.iter().any(|x| x == &survivor) {
                    return ActionResult::Err(game::GameError::Invalid(
                        "invalid_merge_survivor".into(),
                    ));
                }

                s.merge_context = None;
                for loser in ctx.candidates.iter().filter(|cid| *cid != &survivor) {
                    s.payout_merge_bonus_for_company(loser);
                }
                s.merge_settlement = Some(s.build_merge_settlement(
                    &ctx.placed_pos,
                    &ctx.candidates,
                    &survivor,
                ));

                if s.merge_settlement_complete() {
                    if let Err(e) = s.apply_merge(&survivor, &ctx.candidates, &ctx.placed_pos) {
                        return ActionResult::Err(game::GameError::State(e.to_string()));
                    }
                    s.merge_settlement = None;
                    s.phase = "buy".to_string();
                } else {
                    s.phase = "merge_stock_decision".to_string();
                }

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "state": s.snapshot_state(),
                            "event": "merge_resolved",
                            "survivor": survivor,
                            "needs_stock_decision": s.phase == "merge_stock_decision"
                        }),
                    }],
                }
            }
            "merge_stock_decision" => {
                if s.phase != "merge_stock_decision" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_merge_stock_decision".into(),
                    ));
                }

                let settlement = match s.merge_settlement.clone() {
                    Some(v) => v,
                    None => {
                        return ActionResult::Err(game::GameError::State(
                            "missing_merge_settlement".into(),
                        ));
                    }
                };

                let company = action
                    .payload
                    .get("company")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                if company.is_empty() || !settlement.losers.iter().any(|c| c == &company) {
                    return ActionResult::Err(game::GameError::Invalid(
                        "invalid_loser_company".into(),
                    ));
                }

                let mode = action
                    .payload
                    .get("mode")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                let pending_for_user = settlement
                    .pending
                    .get(&action.user_id)
                    .cloned()
                    .unwrap_or_default();
                if !pending_for_user.contains(&company) {
                    return ActionResult::Err(game::GameError::Invalid(
                        "no_pending_decision_for_user_company".into(),
                    ));
                }

                let current_holding = s.share_count(&action.user_id, &company);
                if current_holding <= 0 {
                    if let Some(m) = s.merge_settlement.as_mut()
                        && let Some(set) = m.pending.get_mut(&action.user_id)
                    {
                        set.remove(&company);
                    }
                } else {
                    match mode {
                        "hold" => {
                            // keep as is
                        }
                        "sell" => {
                            let req_qty = action
                                .payload
                                .get("shares")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(current_holding)
                                .max(0)
                                .min(current_holding);
                            let price = s.company_share_price(&company);
                            s.set_share_count(&action.user_id, &company, current_holding - req_qty);
                            *s.players.entry(action.user_id.clone()).or_insert(0) += req_qty * price;
                        }
                        "trade" => {
                            let req_qty = action
                                .payload
                                .get("shares")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(current_holding)
                                .max(0)
                                .min(current_holding);
                            let tradable_old = req_qty - (req_qty % 2);
                            let new_shares = tradable_old / 2;
                            let survivor = settlement.survivor.clone();
                            let pool = s.stock_pool.get(&survivor).copied().unwrap_or(0);
                            if pool < new_shares {
                                return ActionResult::Err(game::GameError::Invalid(
                                    "not_enough_stock_pool_for_trade".into(),
                                ));
                            }
                            s.set_share_count(&action.user_id, &company, current_holding - tradable_old);
                            *s.share_mut(&action.user_id, &survivor) += new_shares;
                            if let Some(p) = s.stock_pool.get_mut(&survivor) {
                                *p -= new_shares;
                            }
                        }
                        _ => {
                            return ActionResult::Err(game::GameError::Invalid(
                                "invalid_merge_stock_mode".into(),
                            ));
                        }
                    }

                    if let Some(m) = s.merge_settlement.as_mut()
                        && let Some(set) = m.pending.get_mut(&action.user_id)
                    {
                        set.remove(&company);
                    }
                }

                let mut event = "merge_stock_decision_applied".to_string();
                if s.merge_settlement_complete() {
                    let final_settlement = s.merge_settlement.clone().expect("checked some");
                    if let Err(e) = s.apply_merge(
                        &final_settlement.survivor,
                        &final_settlement.candidates,
                        &final_settlement.placed_pos,
                    ) {
                        return ActionResult::Err(game::GameError::State(e.to_string()));
                    }
                    s.merge_settlement = None;
                    s.phase = "buy".to_string();
                    event = "merge_finalized".to_string();
                }

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "state": s.snapshot_state(),
                            "event": event,
                            "by": action.user_id
                        }),
                    }],
                }
            }
            "declare_end" => {
                if s.phase != "place" && s.phase != "buy" {
                    return ActionResult::Err(game::GameError::Invalid(
                        "phase_mismatch_expected_place_or_buy".into(),
                    ));
                }
                if !s.can_declare_end() {
                    return ActionResult::Err(game::GameError::Invalid(
                        "end_conditions_not_met".into(),
                    ));
                }

                s.settle_endgame();
                let winner = s
                    .final_standings
                    .first()
                    .map(|x| x.user_id.clone())
                    .unwrap_or_default();

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::All,
                        payload: json!({
                            "type": "state",
                            "state": s.snapshot_state(),
                            "event": "final_scored",
                            "winner": winner
                        }),
                    }],
                }
            }
            "draw_tile" => {
                let hand_size = s
                    .player_tiles
                    .get(&action.user_id)
                    .map(HashSet::len)
                    .unwrap_or(0);
                if hand_size >= 6 {
                    return ActionResult::Err(game::GameError::Invalid(
                        "hand_already_full".into(),
                    ));
                }

                let drawn = s.draw_tile_for_user(&action.user_id);
                let Some(pos) = drawn else {
                    return ActionResult::Err(game::GameError::Invalid(
                        "tile_bag_empty".into(),
                    ));
                };

                ActionResult::Ok {
                    events: vec![],
                    broadcasts: vec![Outbound {
                        target: OutboundTarget::User(action.user_id.clone()),
                        payload: json!({
                            "type": "draw_tile_ok",
                            "user": action.user_id,
                            "tile": pos,
                            "hand": s.player_tiles.get(&action.user_id).cloned().unwrap_or_default(),
                            "remaining": s.tile_bag.len(),
                        }),
                    }],
                }
            }
            _ => ActionResult::Err(game::GameError::Invalid("unknown action type".into())),
        }
    }
}

// (no extra downcast helpers needed; GameState extends Any in the server crate)

