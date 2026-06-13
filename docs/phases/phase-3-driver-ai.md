# Phase 3 — Driver AI Agents (in-game multi-agent system, part 1)

**Goal:** 19 AI cars that race each other and the player convincingly, built on the
`MessageBus` agent system from Phase 0.

**Dev agents:** `race-ai-engineer` (lead) + `physics-engineer` (AI cars reuse the
real physics — no cheating kinematics); `qa-engineer` runs headless race sims.

## Deliverables

- Racing line: precomputed optimal-ish line from the track spline (corner-cutting
  curvature minimization is fine; doesn't need to be truly optimal), with a target
  speed profile derived from the Phase 2 tire/aero limits.
- `AIDriverAgent` with three layers, each unit-testable in isolation:
  - **Control:** pure-pursuit/PID follower that drives the *real* `VehiclePhysics`
    along a given line at a given speed profile.
  - **Tactical:** finite-state behavior — `follow`, `overtake` (pick side, commit,
    complete or abort), `defend` (one move), `avoid` (incident ahead), `pitEntry`.
    Decisions from perception: gaps, closing speeds, relative tire states.
  - **Strategic:** per-driver target pace and aggression from a driver profile
    (skill 0–1, aggression 0–1, consistency 0–1) + tire wear management.
- Perception is bus/world-query based — agents read sanctioned world state, never
  other agents' internals.
- 20-car grid: staggered grid start, first-corner funneling without mass pileups
  (conservatism ramp for the opening lap).
- Driver roster: 20 named drivers / 10 teams with distinct profiles and liveries
  (color tints are enough at this phase).
- Headless race harness in `ApexGPCore`: run N laps × 20 agents with no renderer,
  outputting finishing order + incident log (this is QA's main tool).

## Acceptance criteria

- [ ] `swift test`: control layer holds the racing line within lane tolerance at
      race speed; tactical FSM transitions are unit-tested; headless 5-lap race
      finishes with ≥18/20 cars running and 0 stuck cars.
- [ ] Faster driver profiles finish ahead of slower ones over a 10-lap headless
      race (rank correlation between skill and result).
- [ ] On screen: AI cars visibly overtake each other and defend; no car drives
      through another; player can race wheel-to-wheel without AI teleporting/jittering.
- [ ] 20 cars + player at 60 fps.
