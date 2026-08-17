# Persona Face on iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The procedural persona face (eyes-first, grok-bot register) renders and performs on the Hearth iOS app, driven by the same motion design as the desktop clients.

**Architecture:** Port the three renderer-free face modules (expressions, director, and the pose math) from TypeScript into `HearthCore/Persona/Face/`, render with the orb's proven `TimelineView + Canvas` pattern, and wire four seams: the renderer switch in `HearthMainView`, the `expression` field on `tts_chunk_start`, the amplitude tap that already exists, and a LookTarget lifted from the composer's typing state. Everything is additive; the orb and USDZ paths are untouched.

**Tech Stack:** Swift 5 language mode (see constraints), SwiftUI `Canvas`/`TimelineView`, XCTest (net-new test target), no new dependencies.

**Spec:** `wiki/raw/persona-face-spec.md` in this branch (a copy of valinor `wiki/clients/persona-face.md`). The TypeScript reference implementation is IN THIS BRANCH at `desktop-client/src/lib/face/{expressions,geometry,director}.ts` and `desktop-client/src/components/stage/PersonaFace.tsx` — port semantics and every numeric value from those files verbatim; they are the single source of truth wherever this plan says "port from".

## Global Constraints

- Repo: `D:\Tools\Hearth` (on the Mac: wherever the Hearth clone lives). Branch: `feat/persona-face`. All work commits there; the PR to main is already open (#3).
- Swift language mode is **v5** (`Core/Package.swift:66` `.swiftLanguageMode(.v5)`, app targets `SWIFT_VERSION = 5.0`). Do not enable Swift 6 strict concurrency; the rationale comment at `Core/Package.swift:48-65` explains why. Match the codebase idioms: `@MainActor` + `ObservableObject` for view models, `@Observable @MainActor final class` for leaf helpers (the `PersonaModelLoader` shape, `PersonaModelView.swift:77-79`), closure properties for WS callbacks (`var onX: ((...) -> Void)?`), no actors.
- iOS deployment floor is **26.0** (`Shared.xcconfig:38`) — `Canvas`, `TimelineView`, `@Observable` are unconditionally available; write zero `#available` checks.
- No new SPM dependencies. New face code lives in `Core/Sources/HearthCore/Persona/Face/`.
- Persona JSON decoding stays tolerant: `JSONSerialization` + optional casts with defaults, never strict `Codable`, never `try!`. Reuse `PersonaPalette.num(_:)`-style numeric coercion (`PersonaPalette.swift:113-118`) for geometry floats — do not write a third coercion.
- Angles are radians, `head_bob` is in head-height units, every geometry value is normalised to the head's bounding box — exactly as the spec's pose-channel table defines.
- The face never swallows taps: the stage is tap-to-talk (`HearthMainView.swift:87-92`), so the face view gets `.allowsHitTesting(false)`.
- Commit after every task, conventional format, small diffs.

---

### Task 1: Test target scaffolding

The package has no test target (`Core/Tests` absent; single `.target` in `Core/Package.swift`). The director is designed time-injected precisely to be testable; this task creates the first test target so every later task can carry its own tests.

**Files:**
- Modify: `apple-client/Hearth/Core/Package.swift` (targets array, ~line 40)
- Create: `apple-client/Hearth/Core/Tests/HearthCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: a runnable `swift test` cycle for every later task.

- [ ] **Step 1: Add the test target to Package.swift**

In the `targets:` array, after the existing `.target(name: "HearthCore", ...)` entry:

```swift
.testTarget(
    name: "HearthCoreTests",
    dependencies: ["HearthCore"],
    swiftSettings: [.swiftLanguageMode(.v5)]
),
```

- [ ] **Step 2: Write a smoke test**

`Core/Tests/HearthCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import HearthCore

final class SmokeTests: XCTestCase {
    func testPackageLinks() {
        XCTAssertEqual(HearthState.IDLE, HearthState.IDLE)
    }
}
```

- [ ] **Step 3: Run it**

Run: `cd apple-client/Hearth/Core && swift test`
Expected: 1 test, PASS. (If `swift test` balks at the iOS-only platforms line, run tests through Xcode: `xcodebuild test -scheme Hearth -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — then use that command everywhere this plan says `swift test`.)

- [ ] **Step 4: Commit**

```bash
git add Core/Package.swift Core/Tests
git commit -m "test(core): first test target, for the face director"
```

---

### Task 2: FaceGeometry decoding and the renderer kind

**Files:**
- Modify: `apple-client/Hearth/Core/Sources/HearthCore/Persona/PersonaVisualization.swift`
- Test: `apple-client/Hearth/Core/Tests/HearthCoreTests/PersonaVisualizationTests.swift`

**Interfaces:**
- Produces: `PersonaVisualization.Kind.proceduralFace`, `struct FaceGeometry` (11 `Double` fields, defaults = warm_round), `PersonaVisualization.faceGeometry: FaceGeometry?`, `PersonaVisualization.canRenderFace: Bool`. Task 5's renderer switch and Task 4's view consume these exact names.

- [ ] **Step 1: Write the failing decode test**

```swift
import XCTest
@testable import HearthCore

final class PersonaVisualizationTests: XCTestCase {
    private let faceJSON: [String: Any] = [
        "type": "procedural_face",
        "archetype": "warm_round",
        "geometry": [
            "head_width": 1.0, "head_height": 1.05, "head_roundness": 0.8,
            "eye_size": 0.1, "eye_spacing": 0.38, "eye_height": 0.45,
            "eye_length": 2.4, "eye_tilt": 0.0,
            "mouth_width": 0.34, "mouth_thickness": 0.05, "mouth_curve": 0.26,
        ],
    ]

    func testDecodesProceduralFace() {
        let v = PersonaVisualization.from(visualization: faceJSON, personaName: "Sulivan")
        XCTAssertEqual(v.kind, .proceduralFace)
        XCTAssertTrue(v.canRenderFace)
        XCTAssertEqual(v.faceGeometry?.eyeLength ?? 0, 2.4, accuracy: 1e-9)
        XCTAssertEqual(v.faceGeometry?.eyeSize ?? 0, 0.1, accuracy: 1e-9)
    }

    func testUnknownTypeStillFallsBackToOrb() {
        let v = PersonaVisualization.from(
            visualization: ["type": "holo_projection"], personaName: "X")
        XCTAssertEqual(v.kind, .sphereParticle)
        XCTAssertFalse(v.canRenderFace)
    }

    func testFaceWithoutGeometryDoesNotClaimRenderable() {
        let v = PersonaVisualization.from(
            visualization: ["type": "procedural_face"], personaName: "X")
        XCTAssertEqual(v.kind, .proceduralFace)
        XCTAssertFalse(v.canRenderFace)   // falls back to the orb, like canRenderModel
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PersonaVisualizationTests`
Expected: FAIL — `Kind` has no member `proceduralFace`.

- [ ] **Step 3: Implement**

In `PersonaVisualization.swift`: add the case, the struct, the field, the decode, and the diagnostic for unknown types (survey flag #2 — the silent fallback costs an hour of bring-up otherwise):

```swift
public enum Kind: String {
    case sphereParticle = "sphere_particle"
    case glbAnimated    = "glb_animated"
    case proceduralFace = "procedural_face"
}

/// Appearance only, normalised to the head's own bounding box. Motion never
/// lives here. Defaults are the warm_round archetype so a partial block
/// still renders a face. Spec: wiki/raw/persona-face-spec.md.
public struct FaceGeometry: Sendable {
    public var headWidth = 1.0, headHeight = 1.05, headRoundness = 0.8
    public var eyeSize = 0.1, eyeSpacing = 0.38, eyeHeight = 0.45
    public var eyeLength = 2.4, eyeTilt = 0.0
    public var mouthWidth = 0.34, mouthThickness = 0.05, mouthCurve = 0.26
}
```

Property on `PersonaVisualization`: `public var faceGeometry: FaceGeometry?` and

```swift
/// Face configs missing their geometry fall back to the orb, the same
/// contract canRenderModel uses for clipless models.
public var canRenderFace: Bool { kind == .proceduralFace && faceGeometry != nil }
```

In `from(visualization:personaName:)`, extend the type read:

```swift
if let raw = visualization["type"] as? String {
    if let kind = Kind(rawValue: raw) {
        out.kind = kind
    } else {
        print("PersonaVisualization: unknown type '\(raw)' for \(personaName); rendering the orb")
    }
}
if out.kind == .proceduralFace, let geo = visualization["geometry"] as? [String: Any] {
    var g = FaceGeometry()
    func f(_ key: String, _ def: Double) -> Double { num(geo[key]) ?? def }
    g.headWidth = f("head_width", g.headWidth); g.headHeight = f("head_height", g.headHeight)
    g.headRoundness = f("head_roundness", g.headRoundness)
    g.eyeSize = f("eye_size", g.eyeSize); g.eyeSpacing = f("eye_spacing", g.eyeSpacing)
    g.eyeHeight = f("eye_height", g.eyeHeight); g.eyeLength = f("eye_length", g.eyeLength)
    g.eyeTilt = f("eye_tilt", g.eyeTilt)
    g.mouthWidth = f("mouth_width", g.mouthWidth); g.mouthThickness = f("mouth_thickness", g.mouthThickness)
    g.mouthCurve = f("mouth_curve", g.mouthCurve)
    out.faceGeometry = g
}
```

`num(_:)` here is the same NSNumber/Double/Int coercion as `PersonaPalette.num(_:)` (`PersonaPalette.swift:113-118`) — move it to a shared internal helper or copy it verbatim into this file; do not invent a new one.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PersonaVisualizationTests` — Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/HearthCore/Persona/PersonaVisualization.swift Core/Tests
git commit -m "feat(persona): decode procedural_face geometry, tolerant with an audible fallback"
```

---

### Task 3: FacePose and the expression library

Port of `desktop-client/src/lib/face/expressions.ts` (in this branch). Same channel names, same delta semantics (`scale` multiplicative, `add` additive), same clamps, every numeric value copied verbatim.

**Files:**
- Create: `apple-client/Hearth/Core/Sources/HearthCore/Persona/Face/FaceExpressions.swift`
- Test: `apple-client/Hearth/Core/Tests/HearthCoreTests/FaceExpressionsTests.swift`

**Interfaces:**
- Produces: `enum PoseChannel` (all pose keys), `struct FacePose`, `struct FaceExpression { scale: [PoseChannel: Double]; add: [PoseChannel: Double] }`, `enum ExpressionName: String, CaseIterable` (the 11 names), `let FACE_EXPRESSIONS: [ExpressionName: FaceExpression]`, `func neutralPose(_ g: FaceGeometry) -> FacePose`, `func applyExpression(_ base: FacePose, _ e: FaceExpression, weight: Double) -> FacePose`. Tasks 4-6 consume these names exactly.

- [ ] **Step 1: Write the failing tests** (mirror the desktop's verify suite — these invariants caught real bugs during the original build)

```swift
import XCTest
@testable import HearthCore

final class FaceExpressionsTests: XCTestCase {
    let warm = FaceGeometry()                    // defaults ARE warm_round
    var narrow: FaceGeometry {                   // narrow_precise, from archetypes.json
        var g = FaceGeometry()
        g.headWidth = 0.86; g.headHeight = 1.14; g.headRoundness = 0.55
        g.eyeSize = 0.075; g.eyeSpacing = 0.34; g.eyeHeight = 0.44
        g.eyeLength = 2.9; g.eyeTilt = 0.05
        g.mouthWidth = 0.26; g.mouthThickness = 0.04; g.mouthCurve = 0.05
        return g
    }

    func testListeningLengthensProportionally() {
        let wl = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.listening]!, weight: 1)
        let nl = applyExpression(neutralPose(narrow), FACE_EXPRESSIONS[.listening]!, weight: 1)
        let fw = wl.eyeLength / warm.eyeLength
        let fn = nl.eyeLength / narrow.eyeLength
        XCTAssertEqual(fw, fn, accuracy: 1e-9)
        XCTAssertGreaterThan(fw, 1)
        XCTAssertNotEqual(wl.eyeLength, nl.eyeLength, accuracy: 1e-6)
    }

    func testWeightZeroIsIdentityAndClampsHold() {
        let p = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.surprise]!, weight: 0)
        XCTAssertEqual(p.eyeScaleL, 1, accuracy: 1e-9)
        let layered = applyExpression(
            applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.laughter]!, weight: 1),
            FACE_EXPRESSIONS[.blink]!, weight: 1)
        XCTAssertEqual(layered.eyelidL, 1, accuracy: 1e-9)   // clamped
    }

    func testCharacterInvariants() {
        let sighed = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.sigh]!, weight: 1)
        XCTAssertLessThan(sighed.eyeArc, -0.5)               // pensive droop
        XCTAssertLessThan(sighed.eyeTiltL, 0); XCTAssertGreaterThan(sighed.eyeTiltR, 0)
        let q = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.question]!, weight: 1)
        XCTAssertLessThan(q.eyeScaleR, q.eyeScaleL)          // one eye smaller
        let s = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.surprise]!, weight: 1)
        XCTAssertEqual(s.eyeScaleL, s.eyeScaleR, accuracy: 1e-9)  // symmetric stare
        XCTAssertGreaterThan(s.focus, 0.2)                   // converged
        let d = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.dissatisfaction]!, weight: 1)
        XCTAssertEqual(d.eyelidL, d.eyelidR, accuracy: 1e-9) // level, side-eyed
        XCTAssertGreaterThan(d.gazeX, 0.5)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter FaceExpressionsTests`, FAIL (types not defined).

- [ ] **Step 3: Implement the pose model**

```swift
public enum PoseChannel: String, CaseIterable, Sendable {
    // geometry
    case headWidth, headHeight, headRoundness
    case eyeSize, eyeSpacing, eyeHeight, eyeLength, eyeTilt
    case mouthWidth, mouthThickness, mouthCurve
    // motion-only
    case eyelidL, eyelidR, eyeArc, focus, headBob
    case eyeScaleL, eyeScaleR, eyeTiltL, eyeTiltR, eyeRaiseL, eyeRaiseR
    case gazeX, gazeY, headTilt, mouthOpen, mouthRound
}

/// Geometry plus the channels only motion owns. Kept as a channel map so
/// applyExpression can iterate; typed accessors below keep call sites sane.
public struct FacePose: Sendable {
    public var values: [PoseChannel: Double]
    public subscript(_ c: PoseChannel) -> Double {
        get { values[c] ?? 0 }
        set { values[c] = newValue }
    }
    // accessors used by renderer + tests (add the rest as needed, same pattern)
    public var eyelidL: Double { self[.eyelidL] }
    public var eyelidR: Double { self[.eyelidR] }
    public var eyeArc: Double { self[.eyeArc] }
    public var eyeLength: Double { self[.eyeLength] }
    public var eyeScaleL: Double { self[.eyeScaleL] }
    public var eyeScaleR: Double { self[.eyeScaleR] }
    public var eyeTiltL: Double { self[.eyeTiltL] }
    public var eyeTiltR: Double { self[.eyeTiltR] }
    public var focus: Double { self[.focus] }
    public var gazeX: Double { self[.gazeX] }
    public var mouthOpen: Double { self[.mouthOpen] }
}

public func neutralPose(_ g: FaceGeometry) -> FacePose {
    FacePose(values: [
        .headWidth: g.headWidth, .headHeight: g.headHeight, .headRoundness: g.headRoundness,
        .eyeSize: g.eyeSize, .eyeSpacing: g.eyeSpacing, .eyeHeight: g.eyeHeight,
        .eyeLength: g.eyeLength, .eyeTilt: g.eyeTilt,
        .mouthWidth: g.mouthWidth, .mouthThickness: g.mouthThickness, .mouthCurve: g.mouthCurve,
        .eyelidL: 0, .eyelidR: 0, .eyeArc: 0, .focus: 0, .headBob: 0,
        .eyeScaleL: 1, .eyeScaleR: 1, .eyeTiltL: 0, .eyeTiltR: 0,
        .eyeRaiseL: 0, .eyeRaiseR: 0,
        .gazeX: 0, .gazeY: 0, .headTilt: 0, .mouthOpen: 0, .mouthRound: 0,
    ])
}

public struct FaceExpression: Sendable {
    public var scale: [PoseChannel: Double] = [:]   // v * (1 + delta * w)
    public var add: [PoseChannel: Double] = [:]     // v + delta * w
}

public func applyExpression(_ base: FacePose, _ e: FaceExpression, weight: Double) -> FacePose {
    var pose = base
    if weight == 0 { return pose }
    let w = min(1, max(0, weight))
    for (c, d) in e.scale { pose[c] = pose[c] * (1 + d * w) }
    for (c, d) in e.add { pose[c] = pose[c] + d * w }
    pose[.eyelidL] = min(1, max(0, pose[.eyelidL]))
    pose[.eyelidR] = min(1, max(0, pose[.eyelidR]))
    pose[.eyeArc] = min(1, max(-1, pose[.eyeArc]))
    pose[.focus] = min(1, max(0, pose[.focus]))
    pose[.mouthOpen] = min(1, max(0, pose[.mouthOpen]))
    pose[.mouthRound] = min(1, max(0, pose[.mouthRound]))
    return pose
}
```

- [ ] **Step 4: Port the library data**

`enum ExpressionName: String, CaseIterable` with `neutral, listening, thinking, speaking, blink, laughter, sigh, surprise, question, confirmation, dissatisfaction`. Then `FACE_EXPRESSIONS`, every value copied from `desktop-client/src/lib/face/expressions.ts` (the `EXPRESSIONS` table). Two fully worked entries to fix the mapping convention — snake_case TS keys map to the camelCase `PoseChannel` cases:

```swift
public let FACE_EXPRESSIONS: [ExpressionName: FaceExpression] = [
    .neutral: FaceExpression(),
    .listening: FaceExpression(
        scale: [.eyeLength: 0.12],
        add: [.headTilt: 0.025]),
    .sigh: FaceExpression(
        add: [.eyelidL: 0.85, .eyelidR: 0.85, .eyeArc: -0.85,
              .eyeTiltL: -0.14, .eyeTiltR: 0.14, .gazeY: 0.15, .headTilt: 0.03]),
    // ... port thinking, speaking, blink, laughter, surprise, question,
    // confirmation, dissatisfaction with values verbatim from expressions.ts.
    // The TS file is in this branch; every number there is the tuned truth.
]
```

- [ ] **Step 5: Run to verify pass** — `swift test --filter FaceExpressionsTests`, 3 PASS. If an invariant fails, the ported value diverged from the TS — fix the value, not the test.

- [ ] **Step 6: Commit**

```bash
git add Core/Sources/HearthCore/Persona/Face/FaceExpressions.swift Core/Tests
git commit -m "feat(face): the pose model and expression library, ported verbatim"
```

---

### Task 4: FaceDirector

Port of `desktop-client/src/lib/face/director.ts` — playlists, blink tiers, saccades, sway, transient envelopes with motion layers, the LookTarget. Time-injected: `now` is milliseconds, passed in, never read from a clock inside.

**Files:**
- Create: `apple-client/Hearth/Core/Sources/HearthCore/Persona/Face/FaceDirector.swift`
- Test: `apple-client/Hearth/Core/Tests/HearthCoreTests/FaceDirectorTests.swift`

**Interfaces:**
- Consumes: Task 3's `FacePose`, `applyExpression`, `FACE_EXPRESSIONS`, `neutralPose`.
- Produces:
  ```swift
  public enum FaceState { case idle, listening, thinking, speaking }
  public struct FaceCue: Sendable { public let name: String; public let at: Double }   // ms
  public struct LookTarget: Sendable { public var x, y, focus: Double }                // gaze space
  public final class FaceDirector {
      public init(geometry: FaceGeometry, now: Double)
      public func tick(now: Double, state: FaceState, cue: FaceCue?,
                       speechLevel: Double, reduceMotion: Bool,
                       lookTarget: LookTarget?) -> FacePose
  }
  ```
  Task 5's renderer ticks exactly this. Plain class, no actor — it is only ever touched from the render loop.

- [ ] **Step 1: Write the failing tests** (the desktop's director suite, ported)

```swift
import XCTest
@testable import HearthCore

final class FaceDirectorTests: XCTestCase {
    let warm = FaceGeometry()

    func testIdleVariesGazeAndBlinksCalm() {
        let d = FaceDirector(geometry: warm, now: 0)
        var gazes = Set<String>(); var blinks = 0; var inBlink = false
        var t = 0.0
        while t <= 30_000 {
            let p = d.tick(now: t, state: .idle, cue: nil, speechLevel: 0,
                           reduceMotion: false, lookTarget: nil)
            if t > 2000 { gazes.insert(String(format: "%.2f", p.gazeX)) }
            let closed = p.eyelidL > 0.7
            if closed && !inBlink { blinks += 1; inBlink = true }
            if !closed { inBlink = false }
            t += 16.7
        }
        XCTAssertGreaterThan(gazes.count, 3)
        XCTAssertTrue((3...10).contains(blinks), "calm tier: got \(blinks) blinks in 30s")
    }

    func testTransientEnvelopeLerpsInHoldsAndDecays() {
        let d = FaceDirector(geometry: warm, now: 0)
        _ = d.tick(now: 0, state: .idle, cue: nil, speechLevel: 0,
                   reduceMotion: true, lookTarget: nil)   // snap-settle
        let cue = FaceCue(name: "laughter", at: 100)
        let ramp = d.tick(now: 160, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertTrue(ramp.eyeArc > 0.1 && ramp.eyeArc < 0.9)   // mid-attack
        let hold = d.tick(now: 400, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertGreaterThan(hold.eyeArc, 0.8)
        let gone = d.tick(now: 3200, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertLessThan(gone.eyeArc, 0.05)
    }

    func testSpeechOpensRoundMouthAndListeningWatchesTarget() {
        let d = FaceDirector(geometry: warm, now: 0)
        let talk = d.tick(now: 50, state: .speaking, cue: nil, speechLevel: 0.5,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertGreaterThanOrEqual(talk.mouthOpen, 0.45)
        XCTAssertEqual(talk[.mouthRound], 1, accuracy: 1e-9)
        let watch = d.tick(now: 5000, state: .listening, cue: nil, speechLevel: 0,
                           reduceMotion: true,
                           lookTarget: LookTarget(x: 0, y: 0.9, focus: 0.5))
        XCTAssertGreaterThan(watch[.gazeY], 0.5)   // pulled toward the target
    }

    func testReduceMotionSuppressesBlink() {
        let d = FaceDirector(geometry: warm, now: 0)
        var t = 0.0; var closed = false
        while t <= 20_000 {
            let p = d.tick(now: t, state: .idle, cue: nil, speechLevel: 0,
                           reduceMotion: true, lookTarget: nil)
            if p.eyelidL > 0.5 { closed = true }
            t += 16.7
        }
        XCTAssertFalse(closed)
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL (FaceDirector undefined).

- [ ] **Step 3: Port the director**

Translate `director.ts` top to bottom. The structure, with the timing tables to copy verbatim from the TS:

```swift
public final class FaceDirector {
    private let geometry: FaceGeometry
    private var pose: FacePose
    private var state: FaceState = .idle
    private var beatIndex = 0
    private var beatStartedAt: Double
    private var blinkStartedAt = -1.0
    private var nextBlinkAt: Double
    private var saccade = (x: 0.0, y: 0.0)
    private var nextSaccadeAt: Double
    private var last: Double
    // constants (verbatim from director.ts): EASE_TAU 140; saccade 900-2600ms,
    // amp 0.18/0.1; sway amp 0.014 period 5200; blink tiers CALM/ATTENTIVE/BUSY;
    // ANIMATIONS playlists per state; TRANSIENTS profiles with attack/hold/decay
    // and the laughter/confirmation motion closures; smoothstep transientWeight.
}
```

Composition order in `tick`, identical to the TS: state change resets playlist + blink schedule → advance beat → ease every channel toward the beat pose (`alpha = reduceMotion ? 1 : 1 - exp(-dt / 140)`) → listening look-target pull (0.85 lerp on gazeX/gazeY/focus) → saccades + sway (skip under reduceMotion) → transient envelope + motion layer → blink (tier from the state's animation) → speech (`mouthOpen += level`, `mouthRound = 1`). Playlist `variant()` merging, `transientWeight` smoothstep, and `blinkWeight` (42% close / 58% open of the tier's duration) all port line-for-line; `Math.random()` becomes `Double.random(in: 0...1)`.

- [ ] **Step 4: Run to verify pass** — `swift test --filter FaceDirectorTests`, 4 PASS. The blink-count band and envelope numbers only pass when the timing tables match the TS exactly.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/HearthCore/Persona/Face/FaceDirector.swift Core/Tests
git commit -m "feat(face): the director -- playlists, blink tiers, saccades, envelopes, look target"
```

---

### Task 5: PersonaFaceView — the Canvas renderer

Port of `geometry.ts` + `PersonaFace.tsx`, in the orb's own idiom: `TimelineView(.animation)` driving a pure `Canvas` draw (the `PersonaCanvasView.swift:20-50` + `PersonaOrb.swift:52` template). No `@Published` per-frame state — the director lives in a plain holder the view owns, and the level arrives through a non-published box (survey flag #7: `ttsAmplitude` already republishes at audio rate; the face must not add a second publisher-rate reader).

**Files:**
- Create: `apple-client/Hearth/Core/Sources/HearthCore/Persona/Face/PersonaFaceView.swift`
- Create: `apple-client/Hearth/Core/Sources/HearthCore/Persona/Face/FaceFeed.swift`

**Interfaces:**
- Consumes: Tasks 2-4 (`FaceGeometry`, `FaceDirector`, `FacePose`), `PersonaPalette` (as-is — `glow(for:)` per state), `HearthState`.
- Produces:
  ```swift
  /// Non-published side-channel: amplitude at audio rate, cue + composer
  /// state at event rate. Written by ChatViewModel, read by the render loop.
  @MainActor public final class FaceFeed {
      public static let shared = FaceFeed()
      public var speechLevel: Double = 0
      public var cue: FaceCue?
      public var composerUp: Bool = false
  }

  public struct PersonaFaceView: View {
      public init(geometry: FaceGeometry, state: HearthState,
                  palette: PersonaPalette, reducedMotion: Bool)
  }
  ```
  Task 6 wires `FaceFeed` writes; Task 6 mounts the view.

- [ ] **Step 1: FaceFeed** — exactly the type above, ~15 lines with doc comments. A singleton matches the app's one-stage reality and keeps ChatViewModel decoupled from the view tree.

- [ ] **Step 2: The view skeleton**

```swift
public struct PersonaFaceView: View {
    let geometry: FaceGeometry
    let state: HearthState
    let palette: PersonaPalette
    let reducedMotion: Bool

    @State private var director: FaceDirector?

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            Canvas { ctx, size in
                let nowMs = timeline.date.timeIntervalSinceReferenceDate * 1000
                let d = director ?? FaceDirector(geometry: geometry, now: nowMs)
                if director == nil { DispatchQueue.main.async { director = d } }
                let feed = FaceFeed.shared
                let pose = d.tick(
                    now: nowMs,
                    state: faceState,
                    cue: feed.cue,
                    speechLevel: feed.speechLevel,
                    reduceMotion: reducedMotion,
                    lookTarget: feed.composerUp
                        ? LookTarget(x: 0, y: 1, focus: 0.5) : nil)
                drawFace(ctx: ctx, size: size, pose: pose, palette: palette, state: state)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Persona face")
    }

    /// The face's own state mapping: the composer being up reads as
    /// listening (the LookTarget pose) even though hearthState only says
    /// LISTENING when the microphone is live -- a face-level decision, per
    /// the port notes. LOADING idles.
    private var faceState: FaceState {
        if FaceFeed.shared.composerUp { return .listening }
        switch state {
        case .LISTENING: return .listening
        case .THINKING: return .thinking
        case .SPEAKING: return .speaking
        case .IDLE, .LOADING: return .idle
        }
    }
}
```

- [ ] **Step 3: Port `drawFace` from `geometry.ts`**

One private function, pure, mirroring `facePaths` shape-for-shape into `Canvas` paths. The math ports directly; the SVG-specific bits map as follows:

- Head squircle: four cubics, handle `k = 0.3 + (0.5523 - 0.3) * roundness` — `Path.addCurve(to:control1:control2:)`.
- Eyes: rounded rects via `Path(roundedRect:cornerRadius:)` with `cornerRadius = min(halfW, halfH)`; per-eye lean = `ctx.drawLayer` with a `.rotated(by:)` transform about the eye centre (SVG's `rotate(deg cx cy)`).
- Lid collapse to a thick bar: `halfH = max(halfW * 0.55, halfW * max(0.2, eyeLength) * (1 - lid * 0.95))`, width never widening.
- Arc close (happy `^` / sad droop): the two-quadratic band with `lift = halfW * 1.5 * lid * sign(arc)`, drawn when `lid * abs(arc) > 0.35` — `Path.addQuadCurve`.
- Glints: small circles at `(-0.28 halfW + gazeX * 0.35 halfW, -0.42 * eyeLength * halfW + gazeY * 0.3 * halfW)` from each eye centre, opacity `max(0, 1 - maxLid * 2)`, fill near-white warm.
- Gaze: `gx = clamp(gazeX * hw * 0.45)` against the head's half-width at the eyes' height (`hw * sqrt(1 - dy^2)` minus 1.6 eye half-widths); `gy = gazeY * hh * 0.3`; vergence `converge = focus * eyeHalfW * 0.55` added to the left eye, subtracted from the right.
- Mouths: the crescent (two quadratics, smile belly DOWN in screen space for positive curve) and the round capsule, drawn with opacities `vis * (1 - mouthRound)` / `vis * mouthRound` where `vis = min(1, mouthOpen * 4)`.
- Whole-face transform: translate y by `headBob * hh`, then rotate by `headTilt` about centre — outermost `ctx.translateBy` + `ctx.rotate`.
- Colours: head fill = palette-tinted parchment; ink = a mix of `palette.glow(for: state)` toward roast (~38%), matching the desktop's state-colour wash. Reuse `PersonaPalette.glow(for:)`; a linear `simd_mix` on the `SIMD3<Float>` before converting to `Color` is the whole "color-mix".

- [ ] **Step 4: Build for the simulator** — `xcodebuild -scheme Hearth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`, expect success. (Rendering is verified live in Task 7; there is no snapshot infra and this plan does not add one.)

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/HearthCore/Persona/Face
git commit -m "feat(face): the Canvas renderer, on the orb's TimelineView template"
```

---

### Task 6: Wiring — the renderer switch, the cue, the composer, reduce motion

**Files:**
- Modify: `apple-client/Hearth/Hearth/Views/HearthMainView.swift:176-187` (renderer branch), `:52-55` area (stageState)
- Modify: `apple-client/Hearth/Core/Sources/HearthCore/Transport/HearthWebSocketClient.swift:54, 269-280`
- Modify: `apple-client/Hearth/Core/Sources/HearthCore/ViewModels/ChatViewModel.swift:211-214, 242-258`
- Modify: `apple-client/Hearth/Hearth/Views/BottomInputBar.swift:18` area

**Interfaces:**
- Consumes: Task 5's `PersonaFaceView` + `FaceFeed`, Task 2's `canRenderFace`.

- [ ] **Step 1: The cue over the wire.** In `HearthWebSocketClient.swift`, beside `onTtsSentence` (line 75):

```swift
/// A face expression named by the harness on tts_chunk_start (resolved
/// from the sentence's non-verbal tag at the source). Absent on most chunks.
public var onFaceCue: ((String) -> Void)?
```

and in the `tts_chunk_start` case (after the `onTtsSentence` read, same bag-of-keys style):

```swift
if let expression = chunkInfo["expression"] as? String, !expression.isEmpty {
    onFaceCue?(expression)
}
```

- [ ] **Step 2: Feed writes in ChatViewModel.** Where the client callbacks are bound (near `ChatViewModel.swift:242`):

```swift
client.onFaceCue = { [weak self] name in
    guard self != nil else { return }
    FaceFeed.shared.cue = FaceCue(
        name: name, at: Date.timeIntervalSinceReferenceDate * 1000)
}
```

And one line inside the existing amplitude sink (`ChatViewModel.swift:211-214`), before the `@Published` write: `FaceFeed.shared.speechLevel = Double(amp)`. Do not remove `ttsAmplitude` — the orb still reads it.

`FaceCue.at` uses the same clock as the renderer's `timeline.date.timeIntervalSinceReferenceDate * 1000`; both sides must stay on `timeIntervalSinceReferenceDate` or envelopes never fire.

- [ ] **Step 3: The composer signal.** In `BottomInputBar.swift`, mirror the existing `typing` state outward: wherever `typing` is set (the keyboard affordance at ~line 85 and "Back to voice" at ~line 134), add `FaceFeed.shared.composerUp = typing`. (Survey note: `typing`, not `isInputFocused`, is the right signal — it means "the composer is up" and survives focus loss.)

- [ ] **Step 4: The renderer switch + reduce motion.** In `HearthMainView.swift`, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and restructure `personaStage`'s branch (`:176-187`) from the boolean `if/else` into:

```swift
if viewModel.personaVisualization.canRenderFace,
   let geo = viewModel.personaVisualization.faceGeometry {
    PersonaFaceView(geometry: geo, state: stageState,
                    palette: viewModel.personaPalette, reducedMotion: reduceMotion)
} else if viewModel.personaVisualization.canRenderModel {
    // existing PersonaModelView branch, unchanged
} else {
    PersonaCanvasView(state: stageState, pulse: Double(viewModel.ttsAmplitude),
                      palette: viewModel.personaPalette, reducedMotion: reduceMotion)
}
```

Passing `reducedMotion` to `PersonaCanvasView` connects plumbing that already exists but was never wired (`PersonaCanvasView.swift:24`) — an intentional behaviour change for reduce-motion users on the orb too; say so in the commit message. Use the same `stageState` the stage already computes (the EaselStore THINKING override at `:52-55`), not raw `hearthState`.

- [ ] **Step 5: Build and run on the simulator against a `feat/persona-face` house.** Sulivan's config arrives as `procedural_face` → the face renders. Type into the composer → the eyes drop toward the input. No taps swallowed (stage still toggles the mic).

- [ ] **Step 6: Commit**

```bash
git add Hearth/Views/HearthMainView.swift Hearth/Views/BottomInputBar.swift \
        Core/Sources/HearthCore/Transport/HearthWebSocketClient.swift \
        Core/Sources/HearthCore/ViewModels/ChatViewModel.swift
git commit -m "feat(face): wire the renderer switch, the cue, the composer target, and reduce motion"
```

---

### Task 7: Bundled data, live verification, docs

**Files:**
- Modify: `apple-client/Hearth/Core/Sources/HearthCore/Resources/Personas/sulivan.json:8` area
- Modify: `wiki/clients/ios.md` (Hearth repo)
- Modify: `apple-client/Hearth/Hearth/Views/Persona/PersonaView.swift:78-85` (comment only)

- [ ] **Step 1: Flip the bundled fallback.** Replace the bundled `sulivan.json` `visualization` block with the `procedural_face` + warm_round geometry + the existing `state_colors` kept verbatim — copy the shape from `backend/personas/Sulivan/sulivan.json` in this branch. (Today only `PersonaPalette` reads the bundle, so this is future-proofing, not behaviour.)

- [ ] **Step 2: Comment truth.** `PersonaSurface.usesModelAsset`'s comment block (`PersonaSurface.swift:78-85`) reasons about unknown types; note that `procedural_face` lands in the "not a model" branch deliberately (a face keeps the state-colour editor).

- [ ] **Step 3: Live verification, on a physical iPhone against a `feat/persona-face` house** — the checklist that was verified on desktop, in order:
  1. Idle: gaze drifts, occasional look-aways, slow blinks (3.4-6.2s), breathing sway.
  2. Tap-to-talk still works; LISTENING gets the attentive pose.
  3. Open the composer keyboard: eyes drop toward the input, converged.
  4. Send a question: fast asymmetric thinking beats while the house works.
  5. The reply: the mouth is a round oval opening with the ACTUAL voice, closed within a beat of the audio ending (the tap already smooths; if the mouth flutters, tune the `* 7` gain in `TTSStreamPlayer.swift:243`, nothing in the face).
  6. Ask for a joke: if the reply carries `[laughter]`, the happy-arc chuckle bounce lands on that sentence.
  7. Settings > Accessibility > Reduce Motion on: blink/saccades/sway stop; the mouth still follows the voice.
  8. Switch to Selene (glb) and back: renderer switch survives both directions.
- [ ] **Step 4: Update `wiki/clients/ios.md`** with a Persona Face section: what renders it (`Persona/Face/` in HearthCore), the FaceFeed seam, the LookTarget decision (composer up = listening pose), and a pointer to `wiki/raw/persona-face-spec.md`.
- [ ] **Step 5: Commit and push**

```bash
git add Core/Sources/HearthCore/Resources/Personas/sulivan.json \
        Hearth/Views/Persona/PersonaView.swift wiki/clients/ios.md
git commit -m "feat(face): bundled Sulivan wears the face; iOS wiki learns the system"
git push origin feat/persona-face
```

---

## Out of scope (named so they are decisions)

- **visionOS**: `Hearth Vision` is a template stub with no ChatViewModel; the face there rides the future RealityKit pass (sphere + capsule entities per the spec's porting map), not this plan.
- **Widget**: reads `SharedSnapshot.state` strings only; no face.
- **onSegmentPlaying cue timing**: v1 fires the cue on chunk arrival (desktop parity). Syncing the cue to the karaoke clock (`TTSStreamPlayer.onSegmentPlaying`) is a one-line improvement once v1 is verified — noted, not built.
- **An Animations review panel on iOS**: the desktop's tester panel is desktop-only for now.

## Self-review notes

- Spec coverage: data model (Task 2), expression library (Task 3), director contract incl. look target + reduce motion (Task 4), rendering incl. glints/arcs/state tint (Task 5), harness cue (Task 6), state colors (via PersonaPalette, Task 5), porting-notes fallback behaviour (Task 2's canRenderFace). The spec's "serve the library as JSON from the house" end-state is explicitly not in scope.
- Type consistency: `FaceGeometry`, `FacePose`, `FaceDirector.tick`, `FaceFeed`, `PersonaFaceView.init`, `canRenderFace` are each defined once and consumed by name in later tasks.
