# ApexGP — a 3D F1-style racing game for macOS

ApexGP is a complex 3D Formula-1–style racing game built
natively for macOS in **Swift 6 + SceneKit**. It is developed in clearly defined
**phases**, and features a **multi-agent system both in and out of the game**:

- **In-game agents** — AI drivers, a race engineer, team strategists, a race
  director, and a broadcast director that all communicate over a message bus.
- **Development agents** — specialist Claude Code subagents (physics, race-AI,
  graphics, race-systems, QA) that build and verify the game one phase at a time.

The current playable circuit is **Falcon Ridge**, a ~4 km fictional track with 11
corners, a chicane, banking, and elevation change.

## Quick start

Requires Xcode 26 / Swift 6 on macOS 14+.

```bash
swift build          # compile everything
swift test           # run the ApexGPCore unit tests
swift run ApexGPApp  # launch the game window
open Package.swift   # open the whole project in Xcode
```

### Controls (current build)

| Key | Action |
|-----|--------|
| `W` / `↑` | Throttle |
| `S` / `↓` | Brake |
| `A` / `D` (or `←` / `→`) | Steer (smoothed) |
| `F` | DRS (hold — cuts drag on straights) |
| `E` / `Q` | Gear up / down (in manual mode) |
| `G` | Toggle gearbox auto / manual (starts in AUTO) |
| `H` | Toggle telemetry HUD |
| `R` | Reset car to the grid |
| `C` | Cycle camera: Chase → Cockpit → TV → Free |
| `V` | Next trackside TV camera (while in TV mode) |
| drag / scroll | Orbit & zoom (in Free cam) |

A **game controller** is also supported (left stick to steer, triggers for
throttle/brake, shoulder buttons to shift).

> The car is **drivable** as of Phase 2 — real 4-wheel physics with tires, aero,
> DRS, an 8-speed gearbox, and lockable brakes. Take it for a lap.

## Architecture

The project is a Swift Package with two targets and a clean split between
gameplay logic and presentation:

```
ApexGPApp   (executable — SceneKit/AppKit: rendering, input, HUD, audio)
   │  renders state from / sends input to
ApexGPCore  (library — NO UI imports, fully unit-testable, deterministic)
   ├── Track/    centerline spline, sampling contract, sectors, grid slots, mesh math, surface query
   ├── Physics/  4-wheel vehicle dynamics — tires, aero, drivetrain, brakes, collision, fixed-step sim
   └── Agents/   in-game multi-agent message bus
```

Key rules (see `CLAUDE.md`): all gameplay logic and tests live in `ApexGPCore`
with no SceneKit/AppKit imports; the simulation is deterministic (fixed timestep,
seeded RNG, no wall-clock time); AI cars drive through the same input channel as
the player — no physics cheats.

## Development phases

Each phase has a spec with acceptance criteria in `docs/phases/`. A phase is
"done" only when the QA agent verifies its criteria.

| Phase | Title | Status |
|-------|-------|--------|
| 0 | Foundation (skeleton, message bus, tests, agent defs) | ✅ Done |
| 1 | [Track & world](docs/phases/phase-1-track-world.md) (circuit, mesh, cameras, lighting) | ✅ Done* |
| 2 | [Vehicle physics](docs/phases/phase-2-vehicle-physics.md) (drivable car, tires, aero, input) | ✅ Done* |
| 3 | [Driver AI agents](docs/phases/phase-3-driver-ai.md) (19 AI cars racing) | ⏳ Next |
| 4 | [Race systems & strategy agents](docs/phases/phase-4-race-systems.md) (timing, pits, flags) | ⬜ Planned |
| 5 | [UI, HUD & game modes](docs/phases/phase-5-ui-modes.md) (menus, HUD, Quick Race / Time Trial / Championship) | ⬜ Planned |
| 6 | [Audio, VFX & polish](docs/phases/phase-6-polish.md) (engine sound, particles, replays, 60fps) | ⬜ Planned |
| 7 | [Balancing & release QA](docs/phases/phase-7-qa-release.md) (tuning, soak tests, packaging) | ⬜ Planned |

\* *Phases 1 & 2 pass all headless acceptance criteria (59 unit tests green); the
visual/feel criteria have been confirmed interactively.*

See `PLAN.md` for the full master plan and tech-stack rationale.

## Current state (Phase 2 complete)

**What works today:**

- **Drivable F1 car** with a real 4-wheel simulation in `ApexGPCore`: a
  simplified-Pacejka tire model (load-sensitive grip, progressive breakaway),
  aero (downforce ∝ v², drag, DRS), an 8-speed drivetrain (auto + manual, engine
  braking), brakes with lockup, and weight transfer. Runs on a **fixed 240 Hz
  timestep decoupled from the render loop**, so it's deterministic and
  framerate-independent. Ballpark numbers: **0–300 km/h ≈ 10.5 s**, **300→0 braking
  ≈ 130 m**, top speed ≈ 335 km/h.
- **Keyboard + game-controller input** driving a shared `DriverInput` channel
  (with steering smoothing), and a **telemetry HUD** (speed, gear, RPM, per-tire
  slip, downforce). The car rides the real road surface — climbing the elevation
  and leaning into the banking.
- **Falcon Ridge circuit** built from a closed Catmull-Rom centerline spline
  (4014.6 m, 11 corners, a chicane, banking, 0→15 m elevation, 3 timing sectors).
- **3D world**: light-grey asphalt running wall-to-wall, red/white striped kerbs
  lining the barriers, green grass, a flat checkered start/finish line, a 20-car
  starting grid, and a cosmetic pit apron — all generated procedurally.
- **Camera rig**: chase, cockpit, six trackside TV cameras, and a free orbit cam.
- **Atmosphere**: directional sun + ambient, sky gradient, distance fog.
- **In-game agent backbone**: a publish/subscribe `MessageBus` (deterministic,
  tick-driven) ready for the AI drivers and race agents in Phases 3–4.
- **59 passing unit tests** in `ApexGPCore` covering the track geometry & surface
  query, vehicle dynamics (tire curves, acceleration/braking windows, stability,
  determinism, collision), mesh watertightness, grid layout, and the message bus.

**Not yet implemented:** AI opponents, lap timing, pit stops, audio, and game
modes — these are the subject of Phases 3–7.

## Project layout

```
PLAN.md              Master plan, tech stack, phase roadmap
CLAUDE.md            Project rules for contributors / agents
docs/phases/         One spec per phase, with acceptance criteria
.claude/agents/      Development subagent definitions
Sources/ApexGPCore/  Gameplay library (track, physics, agents) — UI-free, tested
Sources/ApexGPApp/   SceneKit app (rendering, input, cameras, car, HUD)
Tests/               ApexGPCore unit tests
```
