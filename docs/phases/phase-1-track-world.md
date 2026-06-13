# Phase 1 — Track & World

**Goal:** replace the placeholder floor with a real race circuit and a navigable 3D world.

**Dev agents:** `graphics-engineer` (scene, meshes, lighting, cameras) + `race-ai-engineer` (track data model, centerline/racing-line geometry) in parallel; `qa-engineer` to sign off.

## Deliverables

- `Track` model in `ApexGPCore/Track/`: closed Catmull-Rom centerline spline with
  per-point width, banking, and surface type; sampled at fixed arc-length steps.
- One complete circuit defined in data (JSON or Swift literal): ~4 km, 10+ corners,
  a chicane, an elevation change, start/finish straight with grid boxes.
- Track mesh generation in the app target: asphalt ribbon from the spline, kerbs on
  corner apexes, grass/runoff, barriers, simple pit lane geometry.
- Sector lines and timing gates (3 sectors) stored on the track model.
- Camera rig: chase cam, cockpit cam, trackside TV cams (static, look-at), free cam.
  Key to cycle them.
- Directional sun + ambient lighting, skybox, distance fog.

## Acceptance criteria

- [ ] `swift test`: track length, closedness (start point == end point), sector gate
      ordering, and arc-length sampling are unit-tested in `ApexGPCore` (no UI imports).
- [ ] `swift run ApexGPApp` shows the full circuit; free cam can fly the whole lap
      with no holes/z-fighting in the mesh.
- [ ] Camera cycling works; TV cams track a dummy object moving along the centerline.
- [ ] 60 fps with the full track mesh on screen (SCNView statistics overlay).
