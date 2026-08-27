# macOS package handoff (alpha 0.1.0)

The Windows installer and the signed Android APK are built. macOS is the
remaining desktop artifact, and it can only be built on the Mac seat. This is
the whole procedure; it is the ship loop from `wiki/developing.md` with the
Mac-specific parts made explicit.

## What comes out

`target/release/bundle/dmg/Hearth_0.1.0_aarch64.dmg`, at the REPOSITORY
ROOT (and the `.app` beside it under `macos/`). That dmg is the alpha
artifact.

Not `desktop-client/src-tauri/target/`, which is where a standalone crate
would put it. The tauri crate is a member of the root workspace, so cargo
resolves one shared target directory at the workspace root and bundles there.
The build's own closing lines print the two real paths; trust those.

## Prerequisites on the Mac

- Node.js and npm
- A Rust toolchain (`cargo`)
- Python 3 (only if rebuilding the backend env; packaging does not need it)
- Xcode command line tools

## Steps, in order

Every step runs from the repository root unless said otherwise.

1. **Pull the branch.** The alpha is staged on `clients/android-appliance`.

2. **Build the supervisor for macOS.** The bundled resources currently hold
   the Windows binaries (`hearth-supervisor.exe`), which are wrong for this
   target. The pack script stages whatever is at
   `backend/supervisor/target/release/`, so build it on this machine first:

   ```
   cd backend/supervisor
   cargo build --release
   ```

   The pack script gate compares the binary's timestamp against the
   supervisor sources and refuses a stale binary, so build before packing,
   always.

3. **Build the voice engine** (first time on this Mac, or when the pin or
   patches changed):

   ```
   bash scripts/build_omnivoice.sh
   ```

4. **Pack the backend tarball.** The engram-mcp client vendors from a
   sibling checkout; point at wherever it lives on the Mac:

   ```
   ENGRAM_MCP_SRC=../engram-mcp bash scripts/pack_backend.sh
   ```

   If there is no checkout on this machine yet, make one first; the pack
   script hard errors without it, deliberately, because a bundle missing the
   memory client is a silent memory regression:

   ```
   git clone https://github.com/XXJones21/engram-mcp.git ../engram-mcp
   ```

5. **Build the client:**

   ```
   cd desktop-client
   npm install
   npm run tauri build
   ```

## Signing, or the absence of it

The alpha dmg is unsigned and not notarized. Gatekeeper will refuse a plain
double-click on first open. Testers get past it with right-click, Open, Open
anyway, once; after that it opens normally. Say this in whatever note goes
out with the link. Proper Developer ID signing and notarization is a release
task, not an alpha one, and belongs with the TestFlight work since both need
the same Apple developer account.

## Verify before shipping

1. Install the dmg on the Mac itself.
2. First run should reach the hardware scan and plan a model tier (the probe
   decides; an M-series Mac takes the small or medium tier).
3. Complete first run far enough that the house boots and a text turn round
   trips.
4. Sulivan should render as the flame. If the panel shows the plain face,
   the frontend bundle is stale; rebuild from step 5.

## Why the tarball must be repacked here rather than reused

`resources/backend.tar.gz` from the Windows build stages the same Python
source, but the pack script also stages the supervisor binary beside it, and
that binary is per-platform. Repacking on the Mac after step 2 is what puts
the Mach-O supervisor in the bundle.
