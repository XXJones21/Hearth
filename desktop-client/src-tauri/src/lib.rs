mod config_gen;
mod house;
mod probe;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    /* Registered first, per the plugin's own docs: a second launch lands
       here in the FIRST instance, which shows itself; the second process
       exits before its builder runs. */
    .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
      if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
      }
    }))
    .plugin(tauri_plugin_opener::init())
    .plugin(tauri_plugin_dialog::init())
    .manage(house::HouseState::default())
    .invoke_handler(tauri::generate_handler![
      probe::probe_scan,
      probe::probe_plan,
      probe::probe_fixtures,
      probe::probe_model_dir,
      probe::probe_install_root,
      probe::probe_install_state,
      probe::probe_free_disk,
      probe::probe_download,
      config_gen::probe_render_config,
      house::house_start,
      house::house_stop,
      house::house_status,
    ])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      /* The tray is what makes the house outlive the window: an always-on
         companion cannot die because someone closed a chat window. Open
         brings the window back; Quit is the one explicit stop. */
      let open = MenuItem::with_id(app, "open", "Open Hearth", true, None::<&str>)?;
      let quit = MenuItem::with_id(app, "quit", "Quit Hearth", true, None::<&str>)?;
      let menu = Menu::with_items(app, &[&open, &quit])?;
      let mut tray = TrayIconBuilder::with_id("hearth")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .tooltip("Hearth");
      if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
      }
      tray
        .on_menu_event(|app, event| match event.id.as_ref() {
          "open" => {
            if let Some(window) = app.get_webview_window("main") {
              let _ = window.show();
              let _ = window.set_focus();
            }
          }
          "quit" => {
            house::stop(&app.state::<house::HouseState>());
            app.exit(0);
          }
          _ => {}
        })
        .build(app)?;

      Ok(())
    })
    .on_window_event(|window, event| {
      /* Close hides; the backend keeps running. Quit lives in the tray. */
      if let tauri::WindowEvent::CloseRequested { api, .. } = event {
        let _ = window.hide();
        api.prevent_close();
      }
    })
    .build(tauri::generate_context!())
    .expect("error while building tauri application")
    .run(|app, event| {
      /* Belt over the Job Object's braces: an orderly exit stops the tree
         explicitly; a disorderly one is what the kill-on-close job exists
         for. */
      if let tauri::RunEvent::Exit = event {
        house::stop(&app.state::<house::HouseState>());
      }
    });
}
