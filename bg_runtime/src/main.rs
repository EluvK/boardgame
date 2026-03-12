use std::sync::Arc;

use acquire_plugin::AcquireGame;
use boardgames_server::room::RoomManager;
use boardgames_server::server::{run_server, ServerConfig};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // tracing_subscriber::fmt::init();

    let rm = Arc::new(RoomManager::new());

    // create an acquire demo room
    let acquire_game = Arc::new(AcquireGame::new());
    let _ = rm
        .create_room("acquire_demo".to_string(), acquire_game, None)
        .await;

    // load default config
    let cfg: ServerConfig = Default::default();

    run_server(cfg, rm).await?;
    Ok(())
}
