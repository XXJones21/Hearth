use std::path::{Component, PathBuf};

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderValue, Response, StatusCode};
use axum::routing::get;
use axum::Router;
use tokio::fs;
use tower_http::cors::{Any, CorsLayer};

use crate::AppState;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/", get(root))
        .route("/*path", get(asset))
        .layer(CorsLayer::new().allow_origin(Any))
        .with_state(state)
}

async fn root() -> &'static str {
    "Hearth asset server"
}

async fn asset(
    State(state): State<AppState>,
    Path(path): Path<String>,
) -> Result<Response<Body>, StatusCode> {
    let Some(resolved) = safe_join(&state.config.repo_root, &path) else {
        return Err(StatusCode::BAD_REQUEST);
    };
    let bytes = fs::read(&resolved)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;
    let mime = mime_for(&resolved);
    let mut response = Response::new(Body::from(bytes));
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, HeaderValue::from_static(mime));
    Ok(response)
}

fn safe_join(root: &std::path::Path, raw: &str) -> Option<PathBuf> {
    let mut out = PathBuf::from(root);
    for component in PathBuf::from(raw).components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            _ => return None,
        }
    }
    Some(out)
}

fn mime_for(path: &std::path::Path) -> &'static str {
    match path.extension().and_then(|s| s.to_str()).unwrap_or("") {
        "json" => "application/json; charset=utf-8",
        "js" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "html" => "text/html; charset=utf-8",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "wav" => "audio/wav",
        "glb" => "model/gltf-binary",
        "gltf" => "model/gltf+json",
        _ => "application/octet-stream",
    }
}
