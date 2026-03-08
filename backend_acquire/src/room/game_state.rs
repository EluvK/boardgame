use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct GameStateResp {
    pub id: String, // some rand id for each room. first 4 chars of uuid.
    pub status: GameState,
    pub game_stage: GameStage,

    pub users: Vec<UserState>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GameStage {
    UserMove,
    // MeetingProposal,
    // MeetingPublish,
    // MeetingCheck,
    // LastMove,
    GameEnd,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GameState {
    NotStarted,
    Starting,
    Wait(Vec<String>),
    AutoMove,
    End,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct UserState {
    pub id: String,
    pub name: String,
    pub ready: bool,
    // pub location: UserLocationSequence,
    // pub last_move: bool,
    // pub can_locate: bool,
    // pub moves: Vec<Operation>,
    // #[serde(skip)]
    // pub moves_result: Vec<OperationResult>,
    // pub used_token: Vec<SecretToken>,
    // pub is_bot: bool,
}

#[derive(Debug, Clone)]
pub struct ServerGameState {
    // pub map: Map,
    // pub research_clues: Vec<Clue>,
    // pub x_clues: Vec<Clue>,
    // pub user_tokens: HashMap<String, Vec<Token>>,
    // pub terminator_location: Option<UserLocationSequence>,
    // pub revealed_sector_indexs: Vec<usize>,
    // pub choices: HashMap<String, ChoiceFilter>,
}

impl GameStateResp {
    pub fn new(id: String) -> Self {
        Self {
            id,
            status: GameState::NotStarted,
            game_stage: GameStage::UserMove,
            users: vec![],
        }
    }
    pub fn dummy() -> Self {
        Self {
            id: "dummy".to_string(),
            status: GameState::NotStarted,
            game_stage: GameStage::UserMove,
            users: vec![],
        }
    }
}
