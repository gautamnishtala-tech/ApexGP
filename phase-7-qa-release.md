# Phase 7 — Balancing & Release QA

**Goal:** tune it, harden it, ship it.

**Dev agents:** `qa-engineer` (lead) dispatching `physics-engineer` /
`race-ai-engineer` / `race-systems-engineer` for fixes as findings come in.

## Deliverables

- Difficulty calibration: on each difficulty, a target player (defined per level)
  should finish mid-pack; AI lap-time spread tuned per difficulty via headless sims.
- Balance matrix from the headless harness: 100+ simulated races sweeping
  difficulty × tire rule × race length; verify no degenerate strategies (e.g. one
  compound always wins) and incident rates in a sane band.
- Soak tests: 3 full championships back-to-back headless (memory growth < bound,
  no crashes); 2-hour idle-in-menu and pause soak.
- Edge-case sweep: all cars retire, player quits mid-race, controller unplugged
  mid-corner, save-file corruption recovery, window resize/fullscreen mid-race.
- Performance gate re-run on the final build (Phase 6 criteria still hold).
- Packaging: app icon, signed Developer ID build, notarized .dmg via
  `xcodebuild archive` script in `scripts/release.sh`; README with controls.

## Acceptance criteria

- [ ] Balance matrix reviewed and committed to `docs/balance-report.md`.
- [ ] Zero crashes across the soak suite; memory stable over 3 championships.
- [ ] All previous phases' acceptance criteria re-verified green (full regression).
- [ ] Notarized .dmg installs and runs on a clean macOS account.
