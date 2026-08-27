# Selene's model does not load on Android

**Reported:** 2026-08-20, on the Razr, from the shipped `clients/android-client` build.
**Do this after:** the flame port (`tasks/android-client-implementation.md` section 6).

## What happens

Switching to Selene draws nothing recognisable. Her config is
`"type": "glb_animated"`, and the Android stage has no renderer for it -- the
selection in `HearthMainScreen.PersonaStage` only knows a face geometry or the
fallback circle, so a model persona lands in the fallback.

## What the other clients do

| Client | How it draws `glb_animated` |
| --- | --- |
| Apple | `PersonaModelView` mounts RealityKit and loads the **USDZ** clips, one file per state, because RealityKit has no glTF importer. The `usdz` map in the config is Apple-only. |
| Quest | Loads `selene.glb` and addresses the named clips by state. |
| Echo / desktop | Reads the `animations` map -- the same GLB. |

Android is in the third group: it reads **`animations`**, not `usdz`. The pack
is one self-contained binary with named clips `idle` / `Listening` / `T-Pose` /
`Talking` / `Thinking`, served over the assets port.

## What to decide

1. **What renders it.** Filament (`com.google.android.filament:filament-utils-android`)
   is the glTF path with animation support and is what Android XR will want
   later. SceneView wraps it more cheaply. Neither is small.
2. **Where the GLB comes from.** The assets surface serves persona files; the
   client needs to fetch and cache one rather than bundling it, so Sage arrives
   with no client change -- the same contract the renderer selection uses.
3. **What happens while it downloads,** and what happens when it fails. The
   Apple contract is that a model persona with no clips falls back to its orb
   rather than showing an empty stage. Android should match, which means the
   orb from flame-port section 5 is a prerequisite.

## Not in scope

Selene's face. The model carries its own; nothing composites onto it.
