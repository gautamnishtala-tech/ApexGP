# ApexGP — a 3D F1-style racing game for macOS

ApexGP (repo: **F1Game**) is a complex 3D Formula-1–style racing game built
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
| `C` | Cycle camera: Chase → Cockpit → TV → Free |
| `V` | Next trackside TV camera (while in TV mode) |
| drag / scroll | Orbit & zoom (in Free cam) |

> The car is **not yet drivable** — that arrives in Phase 2. Right now the app is
> a world viewer: the full circuit, cameras, and a dummy car lapping the track.

## Architecture

The project is a Swift Package with two targets and a clean split between
gameplay logic and presentation:

```
ApexGPApp   (executable — SceneKit/AppKit: rendering, input, HUD, audio)
   │  renders state from / sends input to
ApexGPCore  (library — NO UI imports, fully unit-testable, deterministic)
   ├── Track/    centerline spline, sampling contract, sectors, grid slots, mesh math
   ├── Physics/  vehicle state & driver input (full dynamics land in Phase 2)
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
| 2 | [Vehicle physics](docs/phases/phase-2-vehicle-physics.md) (drivable car, tires, aero, input) | ⏳ Next |
| 3 | [Driver AI agents](docs/phases/phase-3-driver-ai.md) (19 AI cars racing) | ⬜ Planned |
| 4 | [Race systems & strategy agents](docs/phases/phase-4-race-systems.md) (timing, pits, flags) | ⬜ Planned |
| 5 | [UI, HUD & game modes](docs/phases/phase-5-ui-modes.md) (menus, HUD, Quick Race / Time Trial / Championship) | ⬜ Planned |
| 6 | [Audio, VFX & polish](docs/phases/phase-6-polish.md) (engine sound, particles, replays, 60fps) | ⬜ Planned |
| 7 | [Balancing & release QA](docs/phases/phase-7-qa-release.md) (tuning, soak tests, packaging) | ⬜ Planned |

\* *Phase 1 passes all headless acceptance criteria (30 unit tests green); the
visual criteria have been confirmed interactively.*

See `PLAN.md` for the full master plan and tech-stack rationale.

## Current state (Phase 1 complete)

**What works today:**

- **Falcon Ridge circuit** built from a closed Catmull-Rom centerline spline
  (4014.6 m, 11 corners, a chicane, banking, 0→15 m elevation, 3 timing sectors).
- **3D world**: black asphalt track with white lane edge lines, red/white kerbs on
  corners, perimeter barriers, green grass, a flat checkered start/finish line, a
  20-car starting grid, and a cosmetic pit apron — all generated procedurally from
  the track model.
- **Camera rig**: chase, cockpit, six trackside TV cameras, and a free orbit cam.
- **Atmosphere**: directional sun + ambient, sky gradient, distance fog.
- **In-game agent backbone**: a publish/subscribe `MessageBus` (deterministic,
  tick-driven) ready for the AI drivers and race agents in Phases 3–4.
- **30 passing unit tests** in `ApexGPCore` covering the track geometry, mesh
  watertightness, grid layout, and the message bus.

**Not yet implemented:** driving, AI opponents, lap timing/HUD, pit stops,
audio, and game modes — these are the subject of Phases 2–7.

## Project layout

```
PLAN.md              Master plan, tech stack, phase roadmap
CLAUDE.md            Project rules for contributors / agents
docs/phases/         One spec per phase, with acceptance criteria
.claude/agents/      Development subagent definitions
Sources/ApexGPCore/  Gameplay library (track, physics, agents) — UI-free, tested
Sources/ApexGPApp/   SceneKit app (rendering, input, cameras)
Tests/               ApexGPCore unit tests
```
