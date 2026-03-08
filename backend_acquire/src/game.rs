use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub type PlayerId = String;
pub type GameId = String;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Corporation {
    Sackson,
    Zeta,
    American,
    Worldwide,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Player {
    pub id: PlayerId,
    pub name: String,
    pub cash: i64,
}

impl Player {
    pub fn new(id: impl Into<PlayerId>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            cash: 600,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameState {
    pub id: GameId,
    pub players: HashMap<PlayerId, Player>,
    pub corporations: HashMap<Corporation, i32>,
}

impl GameState {
    pub fn new(id: impl Into<GameId>) -> Self {
        let mut corporations = HashMap::new();
        corporations.insert(Corporation::Sackson, 25);
        corporations.insert(Corporation::Zeta, 25);
        corporations.insert(Corporation::American, 25);
        corporations.insert(Corporation::Worldwide, 25);

        Self {
            id: id.into(),
            players: HashMap::new(),
            corporations,
        }
    }

    pub fn add_player(&mut self, player_id: PlayerId, name: String) {
        let p = Player::new(player_id.clone(), name);
        self.players.insert(player_id, p);
    }

    pub fn buy_shares(
        &mut self,
        player_id: &PlayerId,
        corp: &Corporation,
        shares: i32,
    ) -> Result<(), String> {
        if shares <= 0 {
            return Err("invalid_shares".into());
        }
        let player = self
            .players
            .get_mut(player_id)
            .ok_or_else(|| "player_not_found".to_string())?;
        let avail = self
            .corporations
            .get_mut(corp)
            .ok_or_else(|| "corp_not_found".to_string())?;
        if *avail < shares {
            return Err("not_enough_shares".into());
        }
        // Simplified pricing: 100 per share
        let price = 100i64 * shares as i64;
        if player.cash < price {
            return Err("insufficient_funds".into());
        }
        player.cash -= price;
        *avail -= shares;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GameEvent {
    PlayerJoined {
        player_id: PlayerId,
        name: String,
    },
    BuyShares {
        player_id: PlayerId,
        corp: Corporation,
        shares: i32,
    },
}

impl GameEvent {
    pub fn apply(&self, state: &mut GameState) -> Result<(), String> {
        match self {
            GameEvent::PlayerJoined { player_id, name } => {
                state.add_player(player_id.clone(), name.clone());
                Ok(())
            }
            GameEvent::BuyShares {
                player_id,
                corp,
                shares,
            } => state.buy_shares(player_id, corp, *shares),
        }
    }
}
