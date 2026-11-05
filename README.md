# MyHandball

Desktop handball sandbox built with **Godot 4.3** (GDScript). Phase 0 is a playable move / jump / possess / shoot / score / switch prototype using capsule players and a primitive court — no custom art or animations.

## Requirements (Windows)

1. [Godot 4.3+](https://godotengine.org/download/windows/) (Standard build is enough; .NET not required)
2. This repository cloned locally
3. Keyboard + mouse, and/or a gamepad (both are wired from day one)

## Open & run

1. Install Godot 4.3 (or newer 4.x).
2. Launch Godot → **Import** → select `project.godot` in this folder → **Import & Edit**.
3. Press **F5** (or the Play button). The main scene is `scenes/match/match.tscn`.

If Godot asks to upgrade the project on a newer 4.x, accept and re-run.

### Optional: export a Windows `.exe`

1. In Godot: **Project → Export…**
2. Add a **Windows Desktop** preset (download export templates if prompted).
3. Export to e.g. `build/MyHandball.exe` and run that binary.

## Controls

| Action | Keyboard / mouse | Gamepad |
|--------|------------------|---------|
| Move | WASD | Left stick |
| Jump | Space | A / South |
| Shoot (needs ball) | Left mouse / **E** | RT / R2 |
| Switch teammate | **Q** or Tab | LB / RB (bumpers) |
| Toggle aim mode | **T** | Y / North |

**Aim modes**

- **Face** — shot goes where the capsule is facing (default).
- **Mouse** — shot aims toward the mouse cursor projected onto the court plane.

## Phase 0 sandbox contents

- IHF-ish court (40×20 m units): floor, lines, sideline/end walls, goals with mouth triggers
- **3 outfield + 1 GK** capsules per side (home blue, away red)
- Ball: pickup on contact, follow attach point, impulse shot
- Elevated **3/4 camera** behind the attack; lightly tracks the ball
- Score UI + **GOAL!** flash + automatic reset

Opponent AI is intentionally idle (static dummies). Full rules, networking, and custom art are out of scope for Phase 0.

## Project layout

```
scenes/court/     court.tscn
scenes/actors/    player.tscn, ball.tscn
scenes/match/     match.tscn (main), camera_rig.tscn
scenes/ui/        hud.tscn
scripts/          player, ball, court, camera_rig, goal_area, match_controller, hud
resources/        materials / physics (reserved)
```

## Manual test checklist (§4)

- [ ] Launch → court + home/away capsules + ball + goals visible
- [ ] Move to ball → possess → shoot → ball flies
- [ ] Jump mid-approach → shoot in air
- [ ] Score → GOAL feedback → reset
- [ ] Switch player → move the new capsule
- [ ] Toggle aim Face ↔ Mouse and shoot both ways
- [ ] Gamepad: move / jump / shoot / switch

### Optional automated smoke (dev)

From a terminal (Linux/macOS example; on Windows use Godot’s console or PowerShell):

```bash
godot --path . -- --smoke
```

Expect `SMOKE_OK` after possess → shoot → score → switch.

## License

All rights reserved unless otherwise noted by the repository owner.
