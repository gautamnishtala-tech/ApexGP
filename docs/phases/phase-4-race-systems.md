# Phase 4 — Race Systems & Strategy Agents (in-game multi-agent system, part 2)

**Goal:** turn "cars driving in circles" into a managed race weekend, run by the
remaining in-game agents.

**Dev agents:** `race-systems-engineer` (rules, timing, pits) + `race-ai-engineer`
(engineer/strategy/director agents) in parallel; `qa-engineer` on long-race soaks.

## Deliverables

- Timing system: live lap/sector times from Phase 1 gates, gaps & intervals,
  position tracking, lap validation (track-limit cuts invalidate).
- Tire system: 3 compounds (soft/medium/hard) with wear + grip degradation curves
  feeding the Phase 2 tire model; mandatory pit-stop rule option.
- Pit stops: pit lane speed limiter, stop boxes, stationary time (~2.5 s + variance),
  AI pit entry/exit handled by `AIDriverAgent.pitEntry`.
- `StrategyAgent` (one per team, 2 cars each): plans pit windows pre-race, reacts
  to gaps/degradation/safety cars; posts `pitNow` / `targetPace` orders to its
  drivers over the bus.
- `RaceDirectorAgent`: yellow/green/blue flags by sector, safety car deploy +
  restart (bunch the field, no overtaking), track-limit & collision penalties
  (time penalties applied at pits or added to result).
- `RaceEngineerAgent`: subscribes to player-car telemetry + race events; emits
  prioritized radio messages ("box this lap", "gap behind 1.2", "yellow sector 2")
  rendered as HUD text (audio later).
- Race lifecycle: formation → grid → start lights → race → finish → results,
  with retirements (heavy damage parks the car).

## Acceptance criteria

- [ ] `swift test`: timing math (gaps, intervals, position swaps), wear curves,
      penalty application, and each agent's decision rules are unit-tested with
      scripted bus traffic.
- [ ] Headless 25-lap race: every AI car pits when a mandatory-stop rule is on;
      strategies differ across teams; safety-car deploy + restart preserves order
      and bunches the field.
- [ ] A deliberate corner cut gets the player a penalty; the penalty appears in
      the final classification.
- [ ] Engineer radio messages are relevant and rate-limited (no spam).
