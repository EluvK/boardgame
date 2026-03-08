// pub mod game;
pub mod room;
pub mod server;
pub mod server_state;

use salvo::{Listener, Router, Server, conn::TcpListener, handler, prelude::TowerLayerCompat};

use socketioxide::{SocketIo, extract::State};
use tracing_subscriber::FmtSubscriber;

use server::{StateRef, handle_on_connect, register_state_manager};

#[handler]
async fn hello() -> &'static str {
    "Hello Salvo!"
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let subscriber = FmtSubscriber::new();
    tracing::subscriber::set_global_default(subscriber)?;

    let state = server::create_state();

    let (layer, io) = SocketIo::builder().with_state(state.clone()).build_layer();

    let layer = tower::ServiceBuilder::new()
        .layer(tower_http::cors::CorsLayer::permissive())
        .layer(layer);

    io.ns(
        "/acquire",
        |io: SocketIo, socket, state: State<StateRef>| handle_on_connect(io, socket, state),
    );

    register_state_manager(state, io);

    let layer = layer.compat();
    let router = Router::with_path("/socket.io").hoop(layer).goal(hello);
    let acceptor = TcpListener::new("127.0.0.1:17979").bind().await;
    Server::new(acceptor).serve(router).await;

    Ok(())
}
