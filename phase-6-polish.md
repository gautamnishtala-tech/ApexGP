# Phase 6 — Audio, VFX & Polish

**Goal:** make it look, sound, and feel like a finished racing game.

**Dev agents:** `graphics-engineer` (lead — VFX, replay cameras, performance) +
`race-systems-engineer` (audio hookup, replay data plumbing); `qa-engineer` profiles.

## Deliverables

- Audio (AVAudioEngine): engine pitch/volume from RPM + load (player and doppler-
  shifted nearby AI cars), tire squeal from slip, gearshift/kerb/collision one-shots,
  pit-limiter beep, simple TTS-or-text radio bleep for engineer messages.
- VFX: tire smoke on lockup/wheelspin (SCNParticleSystem), sparks on bottoming,
  gravel/grass kickup, heat haze exhaust (shader modifier), brake glow, rain
  variant: spray plumes + reduced-grip surface (ties into tire model).
- `BroadcastAgent` + replay: ring buffer of car states (last ~60 s + full race at
  reduced rate), TV-director agent picks the most interesting camera (battles,
  incidents) for an auto-replay mode and post-race highlights.
- Track dressing: grandstands, gantries, sponsor boards, pit buildings, trees —
  instanced low-poly assets; time-of-day lighting presets.
- Performance pass: instancing/LOD for AI cars and dressing, physics thread off
  main, target 60 fps with 20 cars + VFX + rain on Apple Silicon.

## Acceptance criteria

- [ ] Engine note tracks RPM continuously through shifts; squeal correlates with
      telemetry slip values.
- [ ] Lockup produces smoke exactly while a tire's slip exceeds threshold.
- [ ] Replay of the last 60 s plays back smoothly with director-chosen cameras.
- [ ] 60 fps sustained over a full 20-car race lap in rain (Instruments capture
      attached to the phase sign-off, no main-thread stalls > 8 ms).
