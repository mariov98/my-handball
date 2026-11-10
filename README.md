# MyHandball

Desktop handball prototype built with **Godot 4.3** (GDScript). **Phase 1** is a mini match on top of the Phase 0 sandbox: both goals score, match clock + periods, kickoff/restart, and basic opponent chase/block AI — still capsules/boxes/spheres only.

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
| Move (camera-relative) | WASD | Left stick |
| Jump | Space | A / South |
| Shoot (needs ball) | Left mouse / **E** | RT / R2 |
| Switch teammate | **Q** or Tab | LB / RB (bumpers) |
| Toggle aim mode | **T** | Y / North |

**Movement** is relative to the **current camera**: W / stick-up walks into the screen along the camera forward projected onto the court. When possession flips and the camera yaws behind the new attack, the same stick direction keeps matching what you see.

**Aim modes**

- **Face** — shot goes where the capsule is facing (default).
- **Mouse** — shot aims toward the mouse cursor projected onto the court plane.

## Phase 1 — mini match

You control **Home** (blue). **Away** (red) runs basic AI. Both ends of the court are live scoring goals.

| Feature | Behavior |
|---------|----------|
| **Clock** | Counts down per period (default **2:00** × **2** halves). Tunable via `period_length_seconds` / `periods_total` on `MatchController`. |
| **Kickoff / restart** | Opening kickoff to Home. After a goal, the **conceding** team restarts from center with possession. Period 2 kickoff goes to Away. Short freeze + banner, then live play. |
| **Opponent AI** | Away outfield: chase free ball, block lanes when defending, support when a teammate carries, drive + shoot near the goal. Away GK tracks the ball laterally on the line. |
| **Camera** | Elevated 3/4 behind the team with (or last with) the ball; smooth flip on possession change. |
| **UI** | Score, clock, period, GOAL / kickoff / period / full-time banners. |

Human teammates (non-controlled Home capsules) stay idle in Phase 1. Full handball rules (steps, passive, 7m), career, and custom art remain out of scope.

### Sandbox period length

Defaults are short for feel-testing. In the Match scene inspector (or in `scripts/match_controller.gd` exports):

- `period_length_seconds` — seconds per half (default `120`)
- `periods_total` — number of periods (default `2`)

## Phase 0 foundation (still in)

- IHF-ish court (40×20 m units): floor, lines, walls, dual goals with mouth triggers
- **3 outfield + 1 GK** capsules per side
- Ball: pickup on contact, follow attach point, impulse shot
- Move / jump / possess / shoot / team switch / camera-relative controls

## Project layout

```
scenes/court/     court.tscn
scenes/actors/    player.tscn, ball.tscn
scenes/match/     match.tscn (main), camera_rig.tscn
scenes/ui/        hud.tscn
scripts/          player, ball, court, camera_rig, goal_area, match_controller, hud
resources/        materials / physics (reserved)
```

## Manual test checklist

### Phase 0 core
- [ ] Launch → court + home/away capsules + ball + goals visible
- [ ] Move to ball → possess → shoot → ball flies
- [ ] Jump mid-approach → shoot in air
- [ ] Switch player → move the new capsule
- [ ] Toggle aim Face ↔ Mouse and shoot both ways
- [ ] Gamepad: move / jump / shoot / switch

### Phase 1 mini match
- [ ] Clock counts down; period label shows P1 / 2
- [ ] Score into **away** goal → GOAL → Away kickoff from center
- [ ] Score into **home** goal (or let AI finish) → Home kickoff
- [ ] Away capsules chase / block (not frozen dummies)
- [ ] Away AI can possess and shoot toward home
- [ ] Period ends at 0:00 → next period or FULL TIME

### Optional automated smoke (dev)

```bash
godot --path . -- --smoke
```

Expect `SMOKE_OK` after cam-relative checks, possess, camera flip, AI chase wish, **both** goals + kickoff sides, and switch.

## License

All rights reserved unless otherwise noted by the repository owner.
