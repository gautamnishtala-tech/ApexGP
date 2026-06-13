# ApexGP — 3D Formula-style Racing Game

A complex 3D F1-style racing game for macOS, built in Xcode with Swift + SceneKit,
developed in phases by a multi-agent workflow, and featuring a multi-agent AI
system *inside* the game (AI drivers, race engineer, strategist, race director).

## Tech stack

| Choice | What | Why |
|---|---|---|
| Language | Swift 6 | Native Xcode toolchain, testable |
| Rendering | SceneKit | Full 3D scene graph, physics hooks, runs everywhere Xcode does; far faster to ship than raw Metal, more game-oriented than RealityKit |
| Project format | Swift Package (`Package.swift`) | Opens directly in Xcode, builds/tests from CLI (`swift build` / `swift test`), no .xcodeproj merge pain |
| Physics | Custom vehicle dynamics in `ApexGPCore` (bicycle model → 4-wheel tire model) | F1 handling needs more fidelity than SceneKit's built-in vehicle physics |
| Targets | macOS first; core library is UI-free so iOS/visionOS ports stay possible | |

## Architecture

```
ApexGPApp  (executable — SceneKit/AppKit: rendering, input, HUD, audio)
    │  renders state from / sends input to
ApexGPCore (library — no UI imports, fully unit-testable)
    ├── Track/     track model, racing line, sector/timing geometry
    ├── Physics/   vehicle dynamics, tires, collisions, fixed-timestep sim
    ├── Agents/    in-game multi-agent system (bus + agents, see below)
    └── Race/      rules, laps, flags, pit stops, championship state
```

## Multi-agent system — IN game (runtime)

All agents communicate over a `MessageBus` (publish/subscribe, ticked at a fixed
rate, decoupled from render framerate). Seeded in Phase 0, built out in Phases 3–4.

| Agent | Role |
|---|---|
| `AIDriverAgent` (×19) | Three-layer driver per AI car: **strategic** (target pace, tire management), **tactical** (overtake / defend / follow / pit-entry decisions), **control** (racing-line following + PID steering/throttle/brake) |
| `RaceEngineerAgent` | Watches the player's car (tire wear, fuel, gaps) and posts radio messages |
| `StrategyAgent` (per team) | Pit windows, tire compound choice, undercut/overcut calls |
| `RaceDirectorAgent` | Flags, safety car, track limits, penalties |
| `BroadcastAgent` | Picks TV cameras / replay moments for spectator & replay mode |

## Multi-agent system — OUT of game (development)

Custom Claude Code subagents live in `.claude/agents/`. Each phase doc says which
agents to dispatch. Typical loop: dispatch specialist agents for a phase's
workstreams (they can run in parallel on independent modules), then `qa-engineer`
verifies the phase's acceptance criteria before moving on.

| Agent | Owns |
|---|---|
| `physics-engineer` | Vehicle dynamics, tires, collisions, numeric stability |
| `race-ai-engineer` | In-game agent system, driver AI, racing line |
| `graphics-engineer` | SceneKit scene, cars/track visuals, cameras, particles, performance |
| `race-systems-engineer` | Rules, timing, pit stops, strategy, HUD/menus |
| `qa-engineer` | Tests, acceptance-criteria verification, regression hunting |

## Phases

Each phase has its own doc in `docs/phases/` with deliverables, acceptance
criteria, and which dev agents to use. A phase is done only when its acceptance
criteria pass.

| Phase | Title | Outcome |
|---|---|---|
| 0 | Foundation *(done — this scaffold)* | Buildable skeleton: SceneKit window, core library, message bus, tests, agent defs |
| 1 | [Track & world](docs/phases/phase-1-track-world.md) | Real circuit from spline data, kerbs/walls, cameras, day lighting |
| 2 | [Vehicle physics](docs/phases/phase-2-vehicle-physics.md) | Drivable car: tire model, aero, gearbox, keyboard/gamepad input |
| 3 | [Driver AI agents](docs/phases/phase-3-driver-ai.md) | 19 AI cars racing each other: racing line, overtaking, defending |
| 4 | [Race systems & strategy agents](docs/phases/phase-4-race-systems.md) | Full race weekend: timing, pits, flags, engineer/strategy/director agents |
| 5 | [UI, HUD & game modes](docs/phases/phase-5-ui-modes.md) | Menus, HUD, telemetry, Quick Race / Time Trial / Championship |
| 6 | [Audio, VFX & polish](docs/phases/phase-6-polish.md) | Engine audio, particles, replays, 60fps performance pass |
| 7 | [Balancing & release QA](docs/phases/phase-7-qa-release.md) | Difficulty tuning, soak tests, packaging |

## How to execute a phase

1. Open the phase doc and read its acceptance criteria.
2. Tell Claude Code: *"Execute Phase N using the dev agents"* — it dispatches the
   listed `.claude/agents/` specialists (parallel where workstreams are independent).
3. `swift build && swift test` must stay green throughout.
4. `qa-engineer` signs off the acceptance criteria; only then start Phase N+1.

## Build & run

```bash
swift build          # compile everything
swift test           # run ApexGPCore unit tests
swift run ApexGPApp  # launch the game window
open Package.swift   # open the whole project in Xcode
```
