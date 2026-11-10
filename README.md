# MyHandball

Desktop handball prototype built with **Godot 4.3** (GDScript). **Phase 2** adds sport-logic approximations (steps, passive play, out of bounds, 6 m goal area, throw-in / goal throw) on top of the Phase 1 mini match — still capsules/boxes/spheres only.

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

## Phase 2 — handball rules core

These are **handball-informed approximations** for a playable prototype — recognizable feel over perfect IHF fidelity. When a rule fires, the HUD shows a banner and a short freeze restart.

| Rule | How it feels in play |
|------|----------------------|
| **Steps / traveling** | While holding the ball on the floor, planar movement accumulates into steps (~1.15 m each). **More than 3** → traveling → free-throw restart for the other team near the spot. Pivot / stand still freely; **jump-shot** (airborne) does not add steps. |
| **Passive play (lite)** | If the carrier stops making progress toward the opponent goal for ~**6 s**, HUD warns **Passive play**. At ~**10 s** → turnover free throw. Meaningful progress (~1.75 m closer to goal) resets the timer. GK holding does not burn passive. |
| **Out of bounds** | Soft sideline / end-line bounds inside the walls. Sideline → **throw-in** for the other team. End line outside the goal mouth: attack last touch → **goal throw** (defending GK); defense last touch → corner-style **throw-in**. |
| **Goal area (6 m)** | Semicircle approx from the goal posts. Outfield players may not stand in either crease; **airborne attackers** can enter for a jump shot. Grounded illegal presence (brief grace) → free throw. Away AI steers outside both arcs. |
| **Restarts** | Throw-in / goal throw / free throw (traveling, passive, 6 m) with short freeze + banner. **Kickoff after goals** (and period starts) from Phase 1 is unchanged. |

HUD also shows a live **Steps n/3** readout (and Passive countdown / PASSIVE) while you hold the ball.

### Intentional simplifications

- No 7 m throws as set pieces, no 2-minute exclusions, no formal 9 m free-throw wall.
- Steps are distance-based, not animated foot plants; no separate dribble / bounce reset.
- Passive is progress-to-goal only (no referee “warning gesture” state machine).
- Goal area is a semicircle distance check, not the full IHF D construction drawings.
- OOB uses soft bounds because walls keep the rigid ball from leaving the arena.

## Phase 1 — mini match (still in)

You control **Home** (blue). **Away** (red) runs basic AI. Both ends of the court are live scoring goals.

| Feature | Behavior |
|---------|----------|
| **Clock** | Counts down per period (default **2:00** × **2** halves). Tunable via `period_length_seconds` / `periods_total` on `MatchController`. |
| **Kickoff / restart** | Opening kickoff to Home. After a goal, the **conceding** team restarts from center with possession. Period 2 kickoff goes to Away. Short freeze + banner, then live play. |
| **Opponent AI** | Away outfield: chase free ball, block lanes when defending, support when a teammate carries, drive + shoot near the goal (outside 6 m). Away GK tracks the ball laterally on the line. |
| **Camera** | Elevated 3/4 behind the team with (or last with) the ball; smooth flip on possession change. |
| **UI** | Score, clock, period, rules status, GOAL / kickoff / rule / period / full-time banners. |

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
scripts/          player, ball, court, camera_rig, goal_area, match_controller,
                  handball_rules, hud
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

### Phase 2 rules
- [ ] Hold ball and run without shooting → Steps HUD climbs → traveling banner → opponent free throw
- [ ] Hold still / weave without approaching goal → Passive warning → turnover free throw
- [ ] Carry or push ball into sideline → throw-in banner for other side
- [ ] Miss end line outside posts → goal throw to defending GK
- [ ] Walk grounded into opponent 6 m with/without ball → goal-area free throw; jump into crease and shoot still works
- [ ] After any rule restart, play returns LIVE and clock still ticks

### Optional automated smoke (dev)

```bash
godot --path . -- --smoke
```

Expect `SMOKE_OK` after Phase 1 checks plus traveling, sideline throw-in, goal throw, goal-area foul, and passive turnover.

## License

All rights reserved unless otherwise noted by the repository owner.
