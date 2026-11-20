use std::env::{self, VarError};
use std::error::Error;
use std::io::{self, IsTerminal};

use axum::Router;
use axum::routing::get;
use listenfd::ListenFd;
use sd_notify::NotifyState;
use tokio::net::TcpListener;
use tokio::signal::unix::{SignalKind, signal};
use tracing_subscriber::EnvFilter;
use tracing_subscriber::filter::LevelFilter;

const DEFAULT_ADDR: &str = "127.0.0.1:3000";

fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        // journald and other log collectors would store the colour codes.
        .with_ansi(io::stdout().is_terminal())
        .with_env_filter(
            EnvFilter::builder()
                .with_default_directive(LevelFilter::INFO.into())
                .from_env()?,
        )
        .init();

    // listenfd unsets LISTEN_FDS and LISTEN_PID, which is only sound before
    // the runtime starts its worker threads.
    let activated = ListenFd::from_env().take_tcp_listener(0)?;

    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(run(activated))
}

async fn run(activated: Option<std::net::TcpListener>) -> Result<(), Box<dyn Error>> {
    let socket_activated = activated.is_some();
    let listener = if let Some(listener) = activated {
        // systemd hands the socket over in blocking mode, which would stall
        // tokio's reactor on the first accept.
        listener.set_nonblocking(true)?;
        TcpListener::from_std(listener)?
    } else {
        let addr = match env::var("LISTEN_ADDR") {
            Ok(addr) => addr,
            Err(VarError::NotPresent) => DEFAULT_ADDR.to_owned(),
            Err(err) => return Err(format!("LISTEN_ADDR: {err}").into()),
        };
        TcpListener::bind(&addr)
            .await
            .map_err(|err| format!("binding {addr}: {err}"))?
    };
    tracing::info!(addr = %listener.local_addr()?, socket_activated, "listening");

    // Installed before READY=1, so a stop that systemd sends straight after
    // startup still shuts down gracefully instead of killing the process.
    let shutdown = shutdown_signal()?;
    sd_notify::notify(&[NotifyState::Ready])?;

    axum::serve(listener, app())
        .with_graceful_shutdown(shutdown)
        .await?;
    Ok(())
}

fn app() -> Router {
    Router::new().route("/health", get(health))
}

async fn health() -> &'static str {
    "ok"
}

fn shutdown_signal() -> io::Result<impl Future<Output = ()>> {
    let mut terminate = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    Ok(async move {
        tokio::select! {
            _ = terminate.recv() => {}
            _ = interrupt.recv() => {}
        }
        tracing::info!("shutting down");
        if let Err(err) = sd_notify::notify(&[NotifyState::Stopping]) {
            tracing::warn!(%err, "could not tell systemd the service is stopping");
        }
    })
}

#[cfg(test)]
mod tests {
    use axum::body::{Body, to_bytes};
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn health_returns_ok() {
        let response = super::app()
            .oneshot(Request::get("/health").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(&body[..], b"ok");
    }
}
