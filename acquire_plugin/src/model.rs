use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompanyState {
    pub id: String,
    pub tiles: HashSet<String>,
    pub safe: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeContext {
    pub placed_pos: String,
    pub candidates: Vec<String>,
    pub allowed_survivors: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeSettlement {
    pub placed_pos: String,
    pub candidates: Vec<String>,
    pub survivor: String,
    pub losers: Vec<String>,
    pub pending: HashMap<String, HashSet<String>>, // user -> loser companies pending decision
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinalStanding {
    pub user_id: String,
    pub cash: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FoundingContext {
    pub tiles: Vec<String>,
}

#[derive(Debug, Clone)]
pub(crate) enum PlacementKind {
    Isolated,
    FoundCandidate,
    Expand(String),
    Merge(Vec<String>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcquireState {
    // minimal playable state
    pub tiles: HashSet<String>,
    pub moves: Vec<(String, String)>, // (user_id, pos)
    pub players: HashMap<String, i64>,
    pub shares: HashMap<String, HashMap<String, i64>>,
    pub stock_pool: HashMap<String, i64>,
    pub tile_bag: VecDeque<String>,
    pub player_tiles: HashMap<String, HashSet<String>>,
    pub independent_tiles: HashSet<String>,
    pub tile_company: HashMap<String, String>,
    pub companies: HashMap<String, CompanyState>,
    pub merge_context: Option<MergeContext>,
    pub merge_settlement: Option<MergeSettlement>,
    pub founding_context: Option<FoundingContext>,
    pub game_over: bool,
    pub final_standings: Vec<FinalStanding>,
    pub turn_order: Vec<String>,
    pub current_turn: usize,
    pub phase: String,
    pub turn_no: u64,
}
