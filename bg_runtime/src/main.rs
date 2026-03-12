use std::sync::Arc;

use acquire_plugin::AcquireGame;
use boardgames_server::room::RoomManager;
use boardgames_server::server::{run_server, ServerConfig};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // tracing_subscriber::fmt::init();

    let rm = Arc::new(RoomManager::new());

    // Register acquire game so lobby list/create APIs can discover it.
    let acquire_game = Arc::new(AcquireGame::new());
    rm.register_game(acquire_game).await;
    let acquire_game_id = "acquire".to_string();

    // Optional demo room for quick local smoke testing.
    let _ = rm
        .create_room_with_game("acquire_demo".to_string(), &acquire_game_id, None)
        .await;

    // load default config
    let cfg: ServerConfig = Default::default();

    run_server(cfg, rm).await?;
    Ok(())
}
