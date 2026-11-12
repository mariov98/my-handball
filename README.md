# MyHandball

Desktop handball prototype built with **Godot 4.3** (GDScript). Phases **0–5** are in: sandbox → mini match → rules → GK/shot craft → tactics → presentation. **Phase A** deepens soft pass circulation; **Phase B** adds **dribble** (hold V / R3) with procedural bounce, a **3-second hold** clock, step reset on dribble catch, and double-dribble lite; **Phase C** remounts **passive play** as an IHF-inspired hybrid (progress warn → pass-count); **Phase D** adds **contact lite** (bump → free throw, clear-chance heuristic → **7 m**, optional **2-min exclusion**). Still engine primitives (polished capsules, no Mixamo).

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
| **Dribble (hold)** | Hold **V** | Hold **R3** (right stick click) |
| **Shoot (hold for power)** | Hold Left mouse / **E** | Hold RT / R2 |
| **PASS** (instant; cancels charge) | Right mouse / **G** | RB (right bumper) |
| **Lob** (while charging shoot) | Hold **F** | Hold LT / L2 |
| **Dive** (GK only) | **C** or Ctrl | B / East |
| **Cycle** teammate | **Q** or Tab | LB (left bumper) |
| **Switch-to-best** | **R** | X / West |
| Toggle aim mode | **T** | Y / North |

**Movement** is relative to the **current camera**: W / stick-up walks into the screen along the camera forward projected onto the court. When possession flips and the camera yaws behind the new attack, the same stick direction keeps matching what you see.

**Camera:** behind the team with (or last with) the ball. In the **center corridor** the frame is square with the goal (goal in the middle). When the ball drifts wide the rig adds only a **subtle yaw** about the ball — it does **not** recenter the ball on screen; the goal stays the visual anchor.

**Team control:** **Q** cycles the Home roster in order. **R** jumps to the most useful teammate (nearest to a free ball, open receiver when attacking, best defender when covering).

**Aim modes**

- **Face** — shot / pass aim follows where the capsule is facing (default).
- **Mouse** — aim toward the mouse cursor projected onto the court plane (lob lifts the shot aim point).

**Pass vs shoot:** Hold **LMB/E/RT** to charge a shot (HUD shows `SHOOT · FLAT/LOB`). Tap **RMB/G/RB** for an instant **PASS** — it cancels any charge and never fires the shot. Passes use a light lead in your aim cone (not a heavy magnet). HUD shows `PASS · RMB / G / RB` while you have the ball and are not charging.

**Dribble vs shoot/pass/jump:** Hold **V** (keyboard) or **R3** (gamepad) to bounce while moving. Chosen so it does not fight shoot (LMB/E/RT), pass (RMB/G/RB), jump (Space/A), or lob (F/LT). Release gathers the ball (new 3 steps + fresh 3 s). Starting a second bounce stream after gather = **double dribble**. Pass and shot clear the 3 s clock. Charging a shot ends an active dribble.

## Phase B — dribble + 3-second hold

| Feature | How it feels in play |
|---------|----------------------|
| **Hold dribble** | Hold **V** / **R3** while possessing → procedural Y bounce + floor probe at troughs (approx continuous stream). |
| **3-second hold** | Without dribble / pass / shot, the Hold pip beside Steps drains; at 3 s → free throw. Warns near 2.4 s. |
| **Dribble catch** | Release dribble → steps reset + 3 s reset (reception zero again). |
| **Double-dribble lite** | After gathering a stream, starting another bounce stream → free throw. |
| **HUD** | `Hold 2.1 ●●●●○○` beside Steps (or `Hold · DRIBBLE` while bouncing). |

### Intentional simplifications (Phase B)

- Continuous bounce without true palm contact (**approx**).
- No AI auto-dribble yet (Away still passes / shoots under step pressure).
- No 7 m / foul ladder in this slice (passive remount is Phase C).

## Phase C — passive play v2 (pass-aware)

**IHF-inspired hybrid** (not full referee AI). Progress/tempo still raises the forewarning; after the signal, a receive-count enforces the turnover.

| Feature | How it feels in play |
|---------|----------------------|
| **Warn trigger** | Stall without meaningful progress toward the opponent goal (~**7 s**) → HUD **Passive (lite)**. Progress (~1.5 m closer) resets/delays the warn only. |
| **Pass-count after warn** | Same-team receives after the warn are counted. Whistle on the **5th receive** without a shot (**N=5**, IHF-like: max 4 passes then whistle on 5th catch). |
| **Shot clears** | A non-pass shot attempt clears the warn + receive count (clarification lite). |
| **GK exempt** | Goalkeeper possession does not burn passive and clears a pending warn. |
| **HUD** | Pre-warn: `Passive (lite) Ns`. After warn: `Passive (lite) r/5` receive counter (stays visible during pass flight). |

### Intentional simplifications (Phase C)

- No full IHF clarification set (e.g. no separate “clear scoring chance” referee judgment beyond shot attempt).
- Post-warn enforcement is **receive-count**, not the old ~11 s wall-clock turnover.
- No fouls / 7 m / formation / camera changes in this slice.

## Phase D — contact lite → 7 m + exclusion lite

Arcade bump → free throw first; clear-chance heuristic → **7 m**; light **2-min exclusion** on 7 m fouls.

| Feature | How it feels in play |
|---------|----------------------|
| **Reach-in / body check** | While you **charge a shot** (or tap pass) near the **6–9 m** arc, a defender inside ~1 m contact volume draws a foul. |
| **Free throw (default)** | Most contact → **FOUL** free throw at the spot + existing 9 m-style wall. |
| **7 m (heuristic)** | **Airborne shooter** inside ~**8 m** + contact from **behind/side** → **7 m** from the mark. Only the defending **GK** may stay on the line; outfield clear outside ~9 m. |
| **Exclusion lite** | Clear-chance **7 m** also benches the fouler (`ai_enabled=false` at sideline marker) for **`exclusion_seconds`** (default 120 s of match clock). Tunable on `MatchController`. |
| **Court** | Visible **7 m** cross marks at both ends. |

### Intentional simplifications (Phase D)

- **Clear-chance detection is heuristic** (airborne + distance + behind/side) — not full IHF referee judgment or progressive personal-foul ladder (warning → 2′ → DQ).
- No animated check / reach-in; proximity volume during windup only.
- Exclusion is a roster hole on the 3-outfield line (huge tactical swing) — keep `exclusion_on_seven_m` / `exclusion_seconds` exports to tune.
- Does not rewrite passive, dribble, formations shapes (beyond 7 m slots), or camera.

## Phase A — pass & catch deepen

Builds on the first-cut soft pass. Feel over features; Phase B owns dribble / 3 s.

| Feature | How it feels in play |
|---------|----------------------|
| **Pass harden** | RMB/G/RB always passes; steal/cancel shoot-charge without releasing a powered shot. |
| **Light lead assist** | Aim cone + slight lead on the receiver; soft in-flight steer + sticky teammate catch. |
| **Show for pass** | Uncontrolled Home teammates step into open wing/CB lanes when a mate has the ball. |
| **Away pressure pass** | Away prefers a teammate pass under pressure or near the step warning before forcing a shot. |

## Phase 5 — presentation pass

Readability and juice **without** reworking gameplay systems. Engine materials + mesh primitives only.

| Feature | How it feels in play |
|---------|----------------------|
| **Court materials** | Warm indoor wood floor, brighter lines, blue/red crease tints, red goal posts + white net, low sideline boards, hall lighting. |
| **Team kits** | Punchier Home blue / Away red, white chest stripe, socks/shoes/shoulders, skin-tone heads, selection rim on the controlled player. |
| **Ball** | Glossy handball orange with dark seam rings; **mesh trail** while the free ball flies (works under OpenGL3). |
| **Goal juice** | Slow-mo (`Engine.time_scale`), full-screen flash, scale-punch **GOAL! HOME/AWAY** banner, score label bump — then kickoff as before. |

### Intentional skips (Phase 5)

- No Mixamo / custom humanoid rigs or animation retargeting (prefer polished capsules).
- No Asset Store shopping / custom modeling pipeline.
- No career / sim depth (Phase 6).
- Trail is mesh dots (not GPU particles) so headless / llvmpipe smoke stays green.

## Phase 4 — tactics lite (still in)

Team-play primitives for **3 outfield + GK**. Spacing is handball-recognizable (wing / backcourt / soft pivot) without full playbooks.

| Feature | How it feels in play |
|---------|----------------------|
| **Formations** | Outfield roles: **LW / CB / RW**. Attack: wings wide near the ~9 m arc, CB in backcourt (tucks pivot-ish when the ball is deep). Defense: 3-across wall outside own 6 m with ball-side slide. Away AI uses the same slots. |
| **Set pieces lite** | Phase 2 restarts now place both teams. Free throws (traveling / passive / 6 m) → taker on the spot + teammates in attack lanes + defenders in a **9 m-style wall**. Throw-in / goal throw get lane / receive shapes. Kickoff uses a compact midfield shape. |
| **Auto off-ball** | Uncontrolled Home teammates (and Away) hold formation slots — no more frozen statues. Free ball: nearest presses, others keep shape. |
| **Switch-to-best** | **R** / X picks ball-nearest, open receiver, or best defender. **Q** remains a simple roster cycle. HUD shows role tags (LW/CB/RW/GK). |

### Intentional simplifications (Phase 4)

- Roles are fixed by roster index (not editable playbooks or custom formations).
- Pivot is a soft CB tuck near the crease, not a dedicated line player + exclusions.
- 9 m wall is a ~3 m gap + free-throw-line bias, not a formal referee-measured wall (7 m is a separate Phase D set piece).
- Off-ball AI steers to slots (no screens, crosses, or scripted combinations).
- Still no career, stamina disciplines, or deep coaching tools.

## Phase 3 — GK + shot craft (still in)

Handball-informed **feel** pass. Primitives only; HUD shows power / jump timing only while relevant.

| Feature | How it feels in play |
|---------|----------------------|
| **Shot power** | Hold shoot to charge (~0.7 s to full). Release to fire. Short tap = softer; full hold = hard flat. HUD power bar + FLAT/LOB % while charging. |
| **Lob** | Hold **F** / LT while charging for a higher, slightly softer floater — useful over a set defense / into the far corner. |
| **Jump-shot timing** | Shoot in the air near the apex for a **sweet** window (bonus impulse, tight scatter). Early / late releases are weaker and a bit wilder. HUD shows `JUMP · sweet/early/late`. |
| **Dedicated GK** | Wider arm boxes + save volume. Faster lateral track on the line. **Dive** (C / Ctrl / B) launches into a low save stretch. Away AI GK predicts flight and dives into the path. Cycle onto Home GK with Q to take the line yourself. |
| **Block traces** | Shots draw a brief aim ribbon. Contested lanes tint warmer. Defenders near the flight path raise arms and can **deflect**; saves/blocks flash a hit marker. Last touch updates for OOB after a tip. |

### Intentional simplifications (Phase 3)

- No stamina / dive stamina meter; dive is cooldown-gated only.
- Block is proximity + “hands up” window, not full animation or foul contact rules.
- Jump sweet spot uses height vs an approximate apex (not a full jump-state machine).
- Charge is binary hold time (no separate analog trigger axis beyond RT as digital shoot).

## Phase 2 — handball rules core (still in)

These are **handball-informed approximations** for a playable prototype — recognizable feel over perfect IHF fidelity. When a rule fires, the HUD shows a banner and a short freeze restart (now with Phase 4 set-piece shapes).

| Rule | How it feels in play |
|------|----------------------|
| **Steps / traveling** | Discrete foot-plants while moving with the ball (~1.8 m gait). Catch gets a **reception zero** (first plant free). Stop / slow = **pivot** (gait pauses; taken steps stay). HUD ticks **Steps n/3** each plant; at 3 a **Last step** warning; a 4th plant → **TRAVELING** free throw. **Jump-shot** (airborne) and **dribbling** do not add steps. Gathering a dribble resets steps. |
| **3-second hold / dribble** | Hold ≤ **3 s** without dribble / pass / shot → free throw. Hold **V** / **R3** to bounce (pauses the clock). Catch the dribble → new 3 s + steps; a second stream after gather → **double dribble**. |
| **Passive play (lite)** | **IHF-inspired hybrid (Phase C):** stall without progress ~**7 s** → **Passive (lite)** warn. After warn, same-team receives count; **5th receive** without a shot → free throw. Meaningful progress (~1.5 m closer) resets/delays the *warn* only. Shot attempt clears; GK possession exempt. |
| **Out of bounds** | Soft sideline / end-line bounds inside the walls. Sideline → **throw-in** for the other team. End line outside the goal mouth: attack last touch → **goal throw** (defending GK); defense last touch → corner-style **throw-in**. |
| **Goal area (6 m)** | Semicircle approx from the goal posts. Outfield players may not stand in either crease; **airborne attackers** can enter for a jump shot. Grounded illegal presence (brief grace) → free throw. Away AI steers outside both arcs. |
| **Restarts** | Throw-in / goal throw / free throw (traveling, passive, 6 m, foul) / **7 m** with short freeze + banner + set-piece placement. **Kickoff after goals** (and period starts) from Phase 1 is unchanged in timing. |
| **Contact / 7 m (Phase D)** | Defender reach-in during shoot/pass windup near 6–9 m → foul FT; clear-chance heuristic → 7 m (+ optional 2-min exclusion). |

HUD shows a large glanceable **Steps n/3** (color + pulse per plant), a **Hold** pip/timer beside it, and a **Passive (lite)** line (timer pre-warn, receive count after). Traveling / 3 s / double dribble / foul / 7 m use red free-throw banners.

## Phase 1 — mini match (still in)

You control **Home** (blue). **Away** (red) runs formation-aware AI. Both ends of the court are live scoring goals.

| Feature | Behavior |
|---------|----------|
| **Clock** | Counts down per period (default **2:00** × **2** halves). Tunable via `period_length_seconds` / `periods_total` on `MatchController`. |
| **Kickoff / restart** | Opening kickoff to Home. After a goal, the **conceding** team restarts from center with possession. Period 2 kickoff goes to Away. Short freeze + banner, then live play. |
| **Opponent AI** | Away outfield: chase free ball, hold defense/attack formation slots, **pass under pressure / at step warning**, drive + shoot near the goal (outside 6 m). Tuned to create pressure but stay beatable. Away GK tracks + dives on shots (less omniscient). |
| **Camera** | Behind the attack; **goal-centered** in the middle corridor; subtle side yaw about the ball; smooth flip on possession change. |
| **UI** | Score, clock, period, steps/rules, shot power, GOAL / kickoff / rule / period / full-time banners. |

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
scripts/          player, ball, ball_trail, court, camera_rig, goal_area, match_controller,
                  handball_rules, shot_craft, pass_craft, block_trace, formations, hud
resources/        materials / physics (reserved)
```

## Manual test checklist

### Phase 0 core
- [ ] Launch → court + home/away capsules + ball + goals visible
- [ ] Move to ball → possess → shoot → ball flies
- [ ] Jump mid-approach → shoot in air
- [ ] Cycle player (Q) → move the new capsule
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
- [ ] Hold ball and run without shooting → Steps HUD pulses 1/3 → 2/3 → 3/3 (warn) → TRAVELING banner → opponent free throw
- [ ] Catch, take 1–2 steps, stop/pivot, resume → steps stay; no sudden silent traveling
- [ ] Hold still / weave without approaching goal → Passive warning → turnover free throw
- [ ] Carry or push ball into sideline → throw-in banner for other side
- [ ] Miss end line outside posts → goal throw to defending GK
- [ ] Walk grounded into opponent 6 m with/without ball → goal-area free throw; jump into crease and shoot still works
- [ ] After any rule restart, play returns LIVE and clock still ticks

### Phase 3 craft
- [ ] Hold shoot → power bar fills → release → harder shot than a tap
- [ ] Hold F/LT while charging → LOB label + higher arc
- [ ] Jump and release near apex → `JUMP · sweet`; early/late labels when mistimed
- [ ] Switch to Home GK → C/Ctrl dive stretches save volume; Away GK dives at shots
- [ ] Shoot through a set defender → warm contested ribbon and/or deflection tip

### Phase 4 tactics
- [ ] Kickoff places wings wide + CB mid (not stacked on spawn spots)
- [ ] Force a free throw → defenders form a wall off the taker; wings/CB fill attack lanes
- [ ] Leave a Home teammate uncontrolled → they drift to wing/backcourt/defense slots
- [ ] Free ball near one teammate → **R** jumps to them; defending → **R** picks the cover man
- [ ] **Q** still cycles roster in order (distinct from **R**)

### Phase 5 presentation
- [ ] Court reads as wood hall with crease tints, red posts, boards
- [ ] Home/Away kits + controlled player rim are obvious at a glance
- [ ] Shoot → orange ball trail follows the shot
- [ ] Score → slow-mo + flash + punchy GOAL banner, then normal-speed kickoff

### Phase A pass deepen
- [ ] With ball, HUD shows **PASS · RMB / G / RB**; hold shoot → **SHOOT** power instead
- [ ] Tap pass while charging → charge cancels; soft pass flies (no powered shot)
- [ ] Circulate wing → CB → wing without needing a shot; steps reset on catch
- [ ] Uncontrolled Home teammates show into open lanes; Away passes when pressed

### Phase B dribble + 3 s
- [ ] Hold **V** / **R3** with ball → bounce animation; HUD shows `Hold · DRIBBLE`
- [ ] Take steps, then dribble and release → Steps reset to 0/3
- [ ] Stand still with ball >3 s (no dribble/pass/shot) → 3 SECONDS free throw
- [ ] Dribble → release → dribble again → DOUBLE DRIBBLE free throw
- [ ] Pass or shoot clears the Hold pip / 3 s clock

### Phase C passive v2
- [ ] Hold / weave without approaching goal → **Passive (lite)** warn
- [ ] After warn, complete 5 team receives without shooting → free throw; HUD shows `Passive (lite) r/5`
- [ ] After warn, shoot → warn clears; further passes do not whistle until a new warn
- [ ] Drive closer to goal before the warn → timer resets / warn delayed
- [ ] GK holding does not show Passive (lite)

### Phase D contact / 7 m
- [ ] Charge a shot near the 6–9 m arc with a defender glued to you → **FOUL** free throw
- [ ] Jump-shot windup inside ~8 m with contact from behind/side → **7 m** banner; taker on the mark
- [ ] On 7 m, only defending GK stays near goal; outfield defenders clear outside ~9 m
- [ ] Clear-chance 7 m → fouler sits on sideline bench briefly (`ai_enabled` off), then returns
- [ ] Court shows 7 m cross marks at both ends

### Optional automated smoke (dev)

```bash
godot --path . -- --smoke
```

Expect `SMOKE_OK` after Phase 1–5 + Phase A–C checks (pass circulation, dribble/hold, passive pass-count).

## License

All rights reserved unless otherwise noted by the repository owner.
