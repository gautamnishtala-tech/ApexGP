# Phase 2 — Vehicle Physics

**Goal:** a player-drivable F1-style car that feels fast, grippy, and breakable at the limit.

**Dev agents:** `physics-engineer` (dynamics, tires, integration) + `graphics-engineer` (car model, wheel animation, input handling) in parallel; `qa-engineer` for the test battery.

## Deliverables

- Fixed-timestep simulation loop in `ApexGPCore` (e.g. 240 Hz physics, decoupled
  from render; render interpolates between physics states).
- `VehiclePhysics`: rigid body with 4-wheel model —
  - Tire model (simplified Pacejka): slip angle/ratio → lateral & longitudinal force,
    load sensitivity, grip falloff past the limit.
  - Aero: downforce ∝ v², drag, simple DRS flag that cuts drag on straights.
  - Drivetrain: torque curve, 8-speed gearbox (auto + manual), engine braking.
  - Brakes with lockup, weight transfer (longitudinal + lateral) affecting tire load.
- Collision: car-vs-barrier (slide + speed scrub) and car-vs-car (impulse) — simple
  capsule/OBB checks against track edges from the Phase 1 model.
- Input: keyboard (WASD/arrows) and game controller via GameController framework,
  with a small input-smoothing filter for keyboard steering.
- Visual car in the app target: placeholder-quality F1 shape (box/wedge primitives or
  a simple .scn asset), spinning wheels, steering animation, brake-light material.
- Debug telemetry overlay: speed, gear, RPM, slip per tire, downforce.

## Acceptance criteria

- [ ] `swift test`: tire-curve shape (peak then falloff), straight-line 0–300 km/h
      time in a plausible F1 window (~9–12 s), braking 300→0 distance plausible
      (~120–160 m), energy doesn't blow up over a 10k-step sim (numeric stability).
- [ ] Drivable lap of the Phase 1 circuit with keyboard: car can be made to
      understeer, oversteer, and lock brakes — and caught again.
- [ ] Hitting a wall at speed scrubs speed and deflects, never tunnels through.
- [ ] Physics identical across framerates (sim is deterministic given same inputs).
