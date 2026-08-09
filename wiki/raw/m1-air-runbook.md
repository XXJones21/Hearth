# M1 Air first run, the runbook

Written 2026-08-07 for the macOS pass. The architecture is one-per-platform
by design, so the Mac path is the same client, the same provisioner, the
same house, reading macOS entries from the same dictionary.

## What the Mac build does differently, all already in the code

- Dictionary carries macOS artifacts: python-build-standalone
  aarch64-apple-darwin (25 MB, sha-verified) and llama.cpp b10298
  macos-arm64 with Metal (11 MB tar.gz; the provisioner strips its
  versioned top directory).
- All interpreter and binary paths are per-platform (bin/python3, no .exe
  anywhere); the renderer writes them, the house reads them.
- Default install root is ~/Hearth, visible, because deleting the folder is
  the uninstall.
- Process reaping: each supervised process leads a process group and is
  killed as one, the unix stand-in for the Windows Job Object.
- The 8 GB Air's plan will say coexist: false. The house honors it: the
  voice engine is provisioned but does NOT boot resident, and the closing
  screen becomes a written first meeting ("today he writes") with one
  button. The take-turns voice is designed, not yet built, and this is the
  honest interim. On a 16 GB Mac coexist is true and the voice test speaks.

## On the Air, in order

1. Prerequisites (one time):
   - Xcode command line tools: xcode-select --install
   - Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   - Node 20+ is already on the machine per the 2026-08-03 note.
2. Get the code: clone or pull github.com/XXJones21/Hearth (Joshua pushes
   from VYTAL first; nothing has been pushed yet as of this writing).
3. Build the supervisor:
   cd backend/supervisor && cargo build --release
   First arm64 build of the crate; if anything unix-side fails to compile,
   fix there, it never compiled on unix before.
4. Pack: bash scripts/pack_backend.sh
   (emits backend.tar.gz + the bare hearth-supervisor binary)
5. Client: cd desktop-client && npm install && npm run tauri build
   Artifacts land in ../target/release/bundle/ (.app and .dmg). The app is
   unsigned: first launch is right-click, Open, Open.
6. Run the app. Expected flow: welcome, scan (first real reading of the
   m1-air-8gb fixture's numbers against the machine it models), E2B pick
   with the honest small-machine warning, ~6.5 GB of downloads, parallel
   provisioning rows, house start, the written meeting screen.
7. What to check, in order of value:
   - The scan against reality: memory pool, free disk (APFS mount-point
     quirk is untested), the tier pick and its arithmetic.
   - E2B coherence: does Sulivan hold a conversation, does he pick tools
     sanely (get_weather is the easy probe). This is the tier most likely
     to embarrass the product and it has NEVER run.
   - Tokens per second feel: Metal on an M1 with E2B Q4_K_M.
   - The house lifecycle: close the window (menu bar keeps it), quit,
     relaunch, boot revalidation.
   - Uninstall: quit, delete ~/Hearth, relaunch lands in setup.
8. Collect: ~/Hearth/logs/* and the plan card contents (a photo is fine).

## Known unknowns, expected to surface

- The supervisor crate on unix at runtime (spawn paths, kill semantics).
- free_disk_for on APFS (/ vs /System/Volumes/Data prefix matching).
- Gatekeeper quarantine on the unpacked llama-server binary: if the house
  fails with a kill/permission error on llama-server, run
  xattr -dr com.apple.quarantine ~/Hearth/runtime and retry; if that is
  the failure, the provisioner learns to strip quarantine itself.
- Whisper on CPU at the Air's speed (server STT; text queries bypass it).
- The voice env on MPS is deliberately out of scope this round.
