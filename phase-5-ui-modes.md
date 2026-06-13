# Phase 5 — UI, HUD & Game Modes

**Goal:** a playable *game* around the simulation: menus, HUD, and three modes.

**Dev agents:** `race-systems-engineer` (modes, state machine, persistence) +
`graphics-engineer` (HUD/menu rendering — SwiftUI overlay over the SCNView, or
SpriteKit overlay scene); `qa-engineer` for flow testing.

## Deliverables

- App state machine: `MainMenu → Setup → Session(Practice/Quali/Race) → Results →
  back`, with pause menu (resume/restart/quit) that actually freezes the sim.
- Main menu + race setup screens: track (the one circuit for now), laps, AI
  difficulty, tire rule, player team/driver pick.
- In-race HUD: position/lap, live timing tower (all 20 cars, gaps), current/last/
  best lap with sector colors, tire compound + wear, speed/gear, mini-map from the
  track spline, engineer radio message area, flag banners.
- Game modes:
  - **Quick Race** — setup → race → results.
  - **Time Trial** — ghost car of your best lap (record/replay input + state),
    persistent best laps per track (JSON in Application Support).
  - **Championship** — 6-round calendar (same circuit OK at this phase, varied
    weather/length), points table (25-18-15-…), standings persistence between runs.
- Post-session results: classification, fastest lap, penalties applied.
- Settings: key rebinding, difficulty (scales AI driver-profile ranges), camera
  defaults, persisted to disk.

## Acceptance criteria

- [ ] Full loop without relaunch: menu → quick race → results → menu → time trial
      → menu → championship round 1–2.
- [ ] Pause genuinely halts physics + agents (timing doesn't drift while paused).
- [ ] Timing tower matches headless-harness ground truth for the same seed.
- [ ] Ghost lap replays within visual tolerance of the recorded lap.
- [ ] Championship standings survive app relaunch.
