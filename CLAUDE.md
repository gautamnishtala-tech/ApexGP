# ApexGP

3D F1-style racing game for macOS. Swift 6 + SceneKit, Swift Package layout
(open `Package.swift` in Xcode, or build from CLI).

## Commands

```bash
swift build          # compile
swift test           # ApexGPCore unit tests — must stay green at all times
swift run ApexGPApp  # launch the game window
```

## The rules that matter

- **Phased development.** `PLAN.md` is the master plan; `docs/phases/phase-N-*.md`
  define each phase's deliverables and acceptance criteria. Work on the current
  phase only; a phase ends when `qa-engineer` verifies its criteria with executed
  evidence.
- **Multi-agent dev workflow.** Specialist subagents are defined in
  `.claude/agents/` (physics-engineer, race-ai-engineer, graphics-engineer,
  race-systems-engineer, qa-engineer). When executing a phase, dispatch the
  agents its phase doc lists — in parallel when their workstreams touch
  different modules — then dispatch qa-engineer to sign off.
- **Core/app split.** `Sources/ApexGPCore` (track, physics, race rules, in-game
  agents) never imports SceneKit/AppKit and is where all gameplay logic and
  tests live. `Sources/ApexGPApp` only renders core state and forwards input.
- **Determinism.** Fixed-timestep sim, seeded RNG only, no wall-clock time in
  gameplay code. Same seed + inputs ⇒ identical race.
- **In-game agents** (AI drivers, race engineer, strategy, race director)
  communicate only via `MessageBus` (`Sources/ApexGPCore/Agents/`). AI cars
  drive through the same `DriverInput` as the player — no physics cheats.
