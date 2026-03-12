use std::sync::Arc;

use salvo::{Router, Server, conn::TcpListener, handler, prelude::TowerLayerCompat};
use socketioxide::SocketIo;
use tokio::sync::Mutex;
use tracing::info;

use boardgames_server::room::RoomManager;
use boardgames_server::server::{ServerState, StateRef, handle_on_connect};

use async_trait::async_trait;
use boardgames_server::game::{
    Action, ActionCtx, ActionResult, Event, Game, GameDescriptor, GameError, GameState, Outbound,
    OutboundTarget,
};

struct DummyState {}
#[async_trait]
impl GameState for DummyState {
    fn apply_event(&mut self, _ev: &Event) {}
    fn snapshot(&self) -> anyhow::Result<Vec<u8>> {
        Ok(vec![])
    }
    fn restore(&mut self, _data: &[u8]) -> anyhow::Result<()> {
        Ok(())
    }
}

struct DummyGame {
    desc: GameDescriptor,
}

#[async_trait]
impl Game for DummyGame {
    fn descriptor(&self) -> &GameDescriptor {
        &self.desc
    }

    async fn create_initial_state(&self, _opts: Option<serde_json::Value>) -> Box<dyn GameState> {
        Box::new(DummyState {})
    }

    async fn handle_action(
        &self,
        _ctx: &ActionCtx,
        _state: &mut dyn GameState,
        action: Action,
    ) -> ActionResult {
        // simple echo: produce one event and broadcast to all
        let ev = Event {
            ty: "echo".to_string(),
            payload: serde_json::json!({"action": action.payload}),
            meta: None,
        };
        let out = Outbound {
            target: OutboundTarget::All,
            payload: serde_json::json!({"event": ev}),
        };
        ActionResult::Ok {
            events: vec![ev],
            broadcasts: vec![out],
        }
    }

    async fn on_join(
        &self,
        _ctx: &ActionCtx,
        _state: &mut dyn GameState,
        _user: String,
    ) -> ActionResult {
        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![],
        }
    }

    async fn on_leave(
        &self,
        _ctx: &ActionCtx,
        _state: &mut dyn GameState,
        _user: String,
    ) -> ActionResult {
        ActionResult::Ok {
            events: vec![],
            broadcasts: vec![],
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let rm = Arc::new(RoomManager::new());

    // create a demo room with DummyGame (optional)
    let demo_game = Arc::new(DummyGame {
        desc: GameDescriptor {
            id: "dummy".into(),
            name: "Dummy".into(),
            min_players: 1,
            max_players: 8,
            version: "0.1".into(),
        },
    });
    let _ = rm.create_room("demo".to_string(), demo_game, None).await;

    // demo room(s) can be created by an external launcher that depends on both
    // `boardgames_server` and desired game plugins. Keep this binary minimal for the library.

    // load configuration from `server_config.json` in current working dir, fallback to defaults
    let config_path = std::path::Path::new("server_config.json");
    let cfg = if config_path.exists() {
        let data = std::fs::read_to_string(config_path)?;
        serde_json::from_str(&data)?
    } else {
        Default::default()
    };

    boardgames_server::server::run_server(cfg, rm).await?;

    Ok(())
}
