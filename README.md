# MyHandball

Desktop handball prototype built with **Godot 4.3** (GDScript). Phases **0–5** are in: sandbox → mini match → rules → GK/shot craft → tactics → presentation. **Phase A** deepens soft pass circulation; **Phase B** adds **dribble** (hold V / R3) with procedural bounce, a **3-second hold** clock, step reset on dribble catch, and double-dribble lite; **Phase C** remounts **passive play** as an IHF-inspired hybrid (progress warn → pass-count); **Phase D** adds **contact lite** (bump → free throw, clear-chance heuristic → **7 m**, optional **2-min exclusion**); **Phase E** adds **attack/defense shape presets** (Wide/Crash · Flat/OneUp); **Phase F** adds **movement craft** (jump-shot state, flat/bounce/lob passes, GK angle-cut + outlet, catch settle); **Phase G** expands to a **full 7** on court (LW/LB/CB/RB/RW/Pivot + GK) with **stamina** and **dead-ball substitutions** (+2 bench). Playability pass: **auto-control** the Home ball carrier, **realistic kickoff** (defense on 6 m / offense pre-mid), and **IHF court lines**. **Wave 5** makes roles feel distinct: attack width + role drives, ball-side marking with help/cover, and off-ball show / cut / pivot seal / clear-out. **Scale:** 1 Godot unit = 1 metre. The playing court is 40 × 20, goals are 3 × 2, and a standing player is about **1.90 m** (a small fraction of the 20 m width). Lines sit on the wood: goal lines, sidelines, center line (no center circle — indoor handball does not use one), 6 m goal-area D, dashed 9 m free-throw line, 1 m 7 m mark, and a short 4 m goalkeeper line. The court lies on a hall floor with walls and a ceiling, and each team’s substitutes sit on a bench outside the sideline. Still engine primitives (modular body parts hair→feet, no Mixamo).

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
| **Shoot (hold for power)** | Hold Left mouse / **E** | Hold **RT / R2** (trigger axis) |
| **PASS** flat (instant; cancels charge) | Right mouse / **G** | RB (right bumper) |
| **PASS** bounce (hold + pass) | Hold **B** + pass | Hold D-pad Left + RB |
| **PASS** lob (hold + pass) | Hold **F** + pass | Hold **LT / L2** + RB |
| **Lob shot** (while charging shoot) | Hold **F** | Hold **LT / L2** |
| **Dive** (GK) / **Shot fake** (outfield w/ ball) | **C** or Ctrl (**X** also shot fake) | B / East |
| **Pass fake** | **Z** | D-pad Right while LIVE with ball |
| **Jab / body fake** | **N** | **L3** (left stick click) |
| **Cycle** teammate | **Q** or Tab | LB (left bumper) |
| **Switch-to-best** | **R** | X / West |
| Toggle aim mode | **T** | Y / North |
| **Toggle attack shape** (Wide ↔ Crash) | **1** | D-pad Up |
| **Toggle defense shape** (6-0 → 5-1 → 3-2-1 → Man) | **2** | D-pad Down |
| **Camera nudge** (yaw / zoom / height) | **[ ]** · **- =** · **PgUp/PgDn** | Right stick |
| **Camera reset** | **Home** or **0** | — |
| **Wing cinematic toggle** | **4** | — |
| **Sprint** (drains stamina) | Hold **Shift** | Hold **Back** / Select |
| **Cycle bench** (sub candidate; stamina-sorted; GK when controlling GK) | **,** (comma) | D-pad Right (dead ball / no ball) |
| **Confirm sub** (dead ball; OF↔OF or GK↔GK) | **.** (period) | **Start** |
| **Help / remap / meta** | **Esc** or **F1** | — |

**Binding notes (Wave 0):** Shoot is the **RT axis** (not L3). Lob is **LT only** so it does not share **Back/Select** with sprint. Pass (RB) always cancels a shoot charge and never fires the shot. Dribble stays on **V / R3** so it does not fight shoot, pass, jump, or lob.

**Binding notes (Wave 3 fakes):** **X** / **C** (outfield) / pad **B** = shot fake; **Z** / D-pad Right (LIVE+ball) = pass fake; **N** / **L3** = jab. Fakes **keep the ball**, cancel any shoot charge, and never fire a shot or pass. They do not share shoot (LMB/E/RT), pass (RMB/G/RB), dribble (V/R3), or shape toggles (1/2). On dead ball, D-pad Right / **,** still cycles the bench.

**Movement** is relative to the **current camera**: W / stick-up walks into the screen along the camera forward projected onto the court. When possession flips and the camera yaws behind the new attack, the same stick direction keeps matching what you see.

**Camera:** behind the team with (or last with) the ball. In the **center corridor** the frame is square with the goal (goal in the middle). When the ball drifts wide the rig adds only a **subtle yaw** about the ball — it does **not** recenter the ball on screen; the goal stays the visual anchor. **Wave 6:** nudge yaw/zoom/height during play (**[ ]** / **- =** / **PgUp/PgDn**, or right stick); **Home/0** resets. Wing finishes get a brief zoom + slow-mo (**4** toggles off). **Shoot cam:** while charging a shot (LMB/E/RT), the camera settles into an over-shoulder close-up behind the shooter's head looking at the attacked goal (tighter FOV), with a **goal-mouth crosshair** for aim. **Right stick** or **mouse move** while holding shoot nudges that crosshair on the goal (Mouse aim mode can also point at the mouth); release fires along that aim and does not fight the charge. Release / cancel restores the elevated 3/4 match cam (wing cinematic still applies on wing finishes; nudge stays blocked only while shoot/wing owns the frame).

**Team control:** While **Home** has the ball, control follows the **carrier** automatically (pickup, catch, GK gather, restart). **Q** still cycles the Home on-court roster (skips bench / exclusions) for off-ball work. **R** jumps to the most useful on-court teammate (nearest to a free ball, open receiver when attacking, best defender when covering). Away possession never forces Away control.

**Shapes (Phase E + Wave 6):** **1** / D-pad↑ toggles Home **attack** Wide (3-3) ↔ Crash (2-4). **2** / D-pad↓ cycles Home **defense** **6-0 → 5-1 → 3-2-1 → Man**. Roles are real **LW / LB / CB / RB / RW / Pivot**. Away AI picks shapes from score/time (incl. 3-2-1 / Man lite). HUD shows `Shape Atk … · Def …`.

**Occupation & marking (Wave 5):** Uncontrolled teammates hold **role-specific** slots (not one chase). Attack keeps wing width and backcourt belt spacing; defense slides **ball-side** while weak-side lanes stay spread. Defenders **mark** the paired threat with pressure toward own goal and **help/cover** cutters/pivot (lite switch/stay). Off-ball: **show-for-pass**, timed **cuts**, pivot **seal/screen** lite, and **clear-out** when crowded.

**Styles & spectacle (Wave 6):** Attack auto-adapts to the facing defense — vs **Man**: open spaces + clear lanes + drive-and-kick; vs **zone**: gaps, ball reversal, backs take ~9 m looks. **Kempa:** airborne catch near the crease redirects toward goal (readable throw, not a teleport).

**Stamina / subs (Phase G):** Hold **Shift** to sprint (drains). Jump and shot also cost stamina; low stamina softens speed and shot accuracy; recovers off-ball (faster on the bench). Substitutions only on whistle / dead ball (kickoff, goal pause, period break, rule restart): **,** cycles the bench candidate, **.** swaps the controlled outfielder with that bench player. HUD shows stamina pips + sub hint.

**Aim modes**

- **Face** — shot / pass aim follows where the capsule is facing (default).
- **Mouse** — aim toward the mouse cursor projected onto the court plane (lob lifts the shot aim point).

**Pass vs shoot:** Hold **LMB/E/RT** to charge a shot (HUD shows `SHOOT · FLAT/LOB`). Tap **RMB/G/RB** for an instant **PASS** — it cancels any charge and never fires the shot. Pass types share that pass button: **flat** alone, **bounce** with **B** / D-pad Left, **lob** with **F** / LT (same lob key as lob-shot while charging). Passes use a light lead in your aim cone (not a heavy magnet). HUD shows `PASS · FLAT/BOUNCE/LOB · RMB/G/RB`.

**Jump-shot craft (Phase F):** With the ball, approach and press **Space** / A → brief **plant** → jump. Release the charged shot inside the timed **window** near apex for sweet timing (feels different from a standing charge). HUD shows plant / rise / window / early·sweet·late.

**Fakes (Wave 3):** Shot fake threatens a release then pulls back; pass fake look-off / pump; jab steps the lead foot + hips. Nearby markers can freeze briefly then recover (lite). AI may fake sparingly under pressure. HUD flashes `Fake · SHOT/PASS/JAB`.

**GK vocabulary (Wave 3):** Set / angle-cut ready stance, lateral shuffle pose, dive **L/R** × **low/high** with matching save volumes, catch/smother vs deflect, outlet windup after a gather. On **7 m**, defending GK starts on the **4 m** line and is restrained from leaving early.

**Dribble vs shoot/pass/jump:** Hold **V** (keyboard) or **R3** (gamepad) to bounce while moving. Chosen so it does not fight shoot (LMB/E/RT), pass (RMB/G/RB), jump (Space/A), or lob (F/LT). Release gathers the ball (new 3 steps + fresh 3 s). Starting a second bounce stream after gather = **double dribble**. Pass and shot clear the 3 s clock. Charging a shot ends an active dribble.

## Phase F — movement craft

| Feature | How it feels in play |
|---------|----------------------|
| **Jump-shot state** | Approach + jump with ball → plant → airborne **release window**; sweet timed release punches harder than a standing shot. |
| **Pass types** | **Flat** chest pass; **bounce** hits the floor then hops to the receiver; **lob** floats over the wall. Same aim (face/mouse). |
| **GK angle-cut** | AI GK steps off the line toward the threat with near-post bias (cuts the angle). |
| **Post-save outlet** | After a save gather, AI GK lobs an outlet to a wing (fast-break lite). |
| **Catch settle** | Fresh catch briefly slows movement so reception reads before the next drive. |

### Intentional simplifications (Phase F)

- Jump plant is a short grounded stick, not full three-step drive animation.
- Bounce pass = floor redirect hop (**approx**), not true spin/palm.
- Outlet is AI-only after saves; human GK keeps distribution manual.
- Career / season / training lite: open with **Esc** (see Phase G table).

## Phase G — sim depth (first playable slice)

| Feature | How it feels in play |
|---------|----------------------|
| **Full 7** | On court: **GK + LW / LB / CB / RB / RW / Pivot**. Bench: **2** outfielders + **1** reserve GK per side. |
| **Stamina** | Sprint / jump / shot drain; soft speed + accuracy when low; recover off-ball / faster on bench. |
| **Subs** | Dead-ball only: **,** cycle bench · **.** confirm. OF↔OF or GK↔reserve GK. Bench pick shows stamina %. |
| **Shapes** | Wide/Crash and Flat/OneUp still work — now with real backs + line player. |
| **Help / remap** | **Esc** / **F1** opens help + remappable keys (saved to `user://input_remap.cfg`). |
| **Meta lite** | Esc menu: **M** season/friendly/training · **T** shoot drill · **H** local hotseat · **K** kit pack. |

### Intentional simplifications (Phase G)

- Season mode is a lite W–D–L record (not a full league calendar).
- No online multiplayer (local hotseat only).
- Subs blocked while LIVE (whistle windows only).
- Sprint is hold-Shift lite — not full energy systems / fatigue injury.

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
- Soft **auto-dribble assist** (Wave 4) can start a legal bounce near the 3 s / last-step limit; HUD shows `Hold · AUTO`. Never forces a double-dribble after gather.
- No 7 m / foul ladder in this slice (passive remount is Phase C; foul ladder is Wave 4).

## Wave 4 — rules helpers & foul ladder

Audits Phase B–D rules up to the requirements checklist bar. Feel-accurate first; labeled **approx** vs **strict** below.

| Feature | How it feels in play | Approx / strict |
|---------|----------------------|-----------------|
| **Hold / step helpers** | Near **~2.55 s** hold or **last step**, soft auto-start dribble if legal. HUD `Hold · AUTO` (still readable). Pass / shoot / takeover (hold **V** then release) ends it. | **approx** soft assist |
| **3 m wall** | Free-throw wall gap ≥ ~**3.2 m**; throw-in / goal-throw opponents held ≥ ~**3 m**. Light **HUD `3 m wall` + floor ring** while the constraint is active; clears after the throw. | **approx** |
| **Head/neck touch → 2′** | Contact vs carrier **HeadRegion** during windup → **2 min** exclusion + FT (reason text). | **approx** (volume + height) |
| **Head hit → red** | Faster approach / airborne fouler into head → **RED** DQ for the match (roster hole). | **approx** severity |
| **Push from behind → 2′** | Strict behind heuristic (front defense stays clean) → **2 min** + FT. | **approx** |
| **Clear chance → 7 m** | Airborne + behind/side ≤~8 m; grounded behind ≤~7 m; illegal crease defense during shot windup. | **heuristic** |
| **FT / 9 m** | Deep fouls snap to the **9 m** line; wall still forms outside. | **approx** |
| **7 m set piece** | Taker on mark; GK on 4 m; ~**5 s** ready limit → goal throw to defense if stalled. | **approx** ready timer |
| **HUD** | Persistent **2′ exclusion pip** (mm:ss + drain bars, both teams) + `RED` rows; `7m Ns` on the rules line; **`3 m wall`** pip + court ring on FT / throw-in / goal-throw. Flash banner still fires on whistle. | — |

### Still healthy after Wave 4

6 m crease, passive (lite), OOB throw-in / goal throw, double-dribble lite — unchanged paths, smoke-covered.

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

## Phase E — roles & shapes on 3+GK

Explicit **shape presets** on the sandbox roster (still LW / CB / RW + GK — no roster expand).

| Feature | How it feels in play |
|---------|----------------------|
| **Attack Wide** | 3-3-ish: wings wide near ~9 m; CB in backcourt with soft pivot only when the ball is deep. |
| **Attack Crash** | 2-4-ish: CB takes a dedicated soft-pivot / line tuck past midfield; wings hold width; ball-side wing can seal a light **screen** between CB and a defender (**approx**). |
| **Defense Flat** | 6-0-ish: 3-across wall outside own 6 m (existing default). |
| **Defense OneUp** | 5-1-ish: wings stay flat; CB steps up toward ~9 m on the ball. |
| **Home toggles** | **1** / D-pad↑ attack · **2** / D-pad↓ defense. Banner flash + HUD `Shape Atk … · Def …`. |
| **Away AI** | Losing → Crash (and OneUp when late or down by 2+); winning → Wide/Flat; tied late → Crash/OneUp. |
| **HUD labels** | Roles stay LW/CB/RW; CB may display as **LB/RB** by ball side (cosmetic teaching). |

### Intentional simplifications (Phase E)

- Still **3 outfield + GK** — no LB/RB/P as separate bodies; Crash pivot is a CB tuck, not a dedicated line player.
- Screen is a slot bias (**approx**), not collision sealing or scripted combinations.
- No Phase F movement craft / jump-shot state machine; no fouls/passive/dribble/camera rewrites.

## Phase A — pass & catch deepen

Builds on the first-cut soft pass. Feel over features; Phase B owns dribble / 3 s.

| Feature | How it feels in play |
|---------|----------------------|
| **Pass harden** | RMB/G/RB always passes; steal/cancel shoot-charge without releasing a powered shot. |
| **Light lead assist** | Aim cone + slight lead on the receiver; soft in-flight steer + sticky teammate catch. |
| **Show for pass** | Uncontrolled Home teammates step into open wing/CB lanes when a mate has the ball. |
| **Away pressure pass** | Away prefers a **forward** teammate pass under pressure / step warning; open 9 m and crease looks shoot instead of recycling. |

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
| **Set pieces lite** | Phase 2 restarts now place both teams. Free throws (traveling / passive / 6 m) → taker on the spot + teammates in attack lanes + defenders in a **9 m-style wall**. Throw-in / goal throw get lane / receive shapes. Kickoff: offense in own half approaching midfield; defense walls just outside own **6 m**. |
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
| **Steps / traveling** | Discrete foot-plants while moving with the ball (~1.8 m gait). Catch gets a **reception zero** (first plant free). Stop / slow = **pivot** (gait pauses; taken steps stay). HUD ticks **Steps n/3** each plant (plus a subtle **Pivot L/R** cue while holding); at 3 a **Last step** warning; a 4th plant → **TRAVELING** free throw. **Jump-shot** (airborne) and **dribbling** do not add steps. Gathering a dribble resets steps. While holding without dribbling, the **pivot foot** (warm shoe + floor ring) stays distinct from the free foot so the 3-step rule teaches itself. |
| **3-second hold / dribble** | Hold ≤ **3 s** without dribble / pass / shot → free throw. Hold **V** / **R3** to bounce (pauses the clock). Catch the dribble → new 3 s + steps; a second stream after gather → **double dribble**. Wave 4 soft assist may auto-start a legal dribble near the limit (`Hold · AUTO`). |
| **Passive play (lite)** | **IHF-inspired hybrid (Phase C):** stall without progress ~**7 s** → **Passive (lite)** warn. After warn, same-team receives count; **5th receive** without a shot → free throw. Meaningful progress (~1.5 m closer) resets/delays the *warn* only. Shot attempt clears; GK possession exempt. |
| **Out of bounds** | Soft sideline / end-line bounds inside the walls. Sideline → **throw-in** for the other team. End line outside the goal mouth: attack last touch → **goal throw** (defending GK); defense last touch → corner-style **throw-in**. |
| **Goal area (6 m)** | IHF stadium shape (3 m straight + quarter-circles at the posts) for collision and painted lines; dashed **9 m** free-throw arcs; **7 m** marks; center line + circle. Outfield players may not stand in either crease; **airborne attackers** can enter for a jump shot. Grounded illegal presence (brief grace) → free throw. Away AI steers outside both arcs. |
| **Restarts** | Throw-in / goal throw / free throw (traveling, passive, 6 m, foul) / **7 m** with short freeze + banner + set-piece placement. **Kickoff after goals** (and period starts) from Phase 1 is unchanged in timing. Deep FTs snap to **9 m**; throw-in / FT walls keep ~**3 m** gap. |
| **Contact / foul ladder (Phase D + Wave 4)** | Windup contact near 6–9 m → FT; head/neck touch → 2′; head hit → red; push from behind → 2′; clear-chance heuristic → 7 m (+ exclusion). |

HUD shows a large glanceable **Steps n/3** (color + pulse per plant; **Pivot L/R** while holding without dribbling), a **Hold** pip/timer beside it (`DRIBBLE` / `AUTO`), a **Passive (lite)** line, a persistent **2′ exclusion pip** (mm:ss + drain bars for both teams; `RED` rows for DQs), a light **`3 m wall`** pip + floor ring on free-throw / throw-in / goal-throw, and 7 m ready clocks. Traveling / 3 s / double dribble / foul / 7 m use red free-throw banners.

## Phase 1 — mini match (still in)

You control **Home** (blue). **Away** (red) runs formation-aware AI. Both ends of the court are live scoring goals.

| Feature | Behavior |
|---------|----------|
| **Clock** | Counts down per period (default **2:00** × **2** halves). Tunable via `period_length_seconds` / `periods_total` on `MatchController`. |
| **Kickoff / restart** | Opening kickoff to Home. After a goal, the **conceding** team restarts from center with possession. Period 2 kickoff goes to Away. Short freeze + banner, then live play. |
| **Opponent AI** | Away outfield: chase free ball, hold slots, **forward pass under pressure**, take open **9 m / crease** shots, avoid endless back-passes. Match soft-lock guards recover orphaned balls / carrier desync. Tuned to create pressure but stay beatable. Away GK tracks + dives. |
| **Camera** | Behind the attack; **goal-centered** in the middle corridor; subtle side yaw about the ball; smooth flip on possession change. |
| **UI** | Score, clock, period, steps/rules, shot power, GOAL / kickoff / rule / period / full-time banners. |

### Sandbox period length

Defaults are short for feel-testing. In the Match scene inspector (or in `scripts/match_controller.gd` exports):

- `period_length_seconds` — seconds per half (default `120`)
- `periods_total` — number of periods (default `2`)

## Phase 0 foundation (still in)

- IHF court (40×20 m units): floor, 6 m D / dashed 9 m / 7 m / center circle, walls, dual goals (3×2) with mouth triggers
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

### Wave 4 rules helpers & foul ladder
- [ ] Stand still near 3 s without pressing V → `Hold · AUTO` soft dribble; no whistle; after gather, second dribble → DOUBLE DRIBBLE
- [ ] Take 3 steps → soft auto-dribble before traveling
- [ ] Contact to head/neck (light) → **2 min** + FT; HUD exclusion clock
- [ ] Hard/airborne head contact → **RED** banner; fouler stays off
- [ ] Push from behind (not front defense) → **2 min** + FT
- [ ] Deep foul spot → restart on / outside **9 m**; throw-in defenders ≥ ~3 m off
- [ ] Stall on 7 m mark ~5 s → goal throw to defense

### Phase E shapes
- [ ] **1** toggles attack Wide ↔ Crash; HUD / banner update; Crash tucks CB toward the 6 m line
- [ ] **2** toggles defense Flat ↔ OneUp; OneUp steps CB up toward ~9 m
- [ ] Uncontrolled teammates / Away slots follow the active shape
- [ ] Away losing late uses Crash / OneUp; winning uses Wide / Flat
- [ ] Controlling CB with ball wide can show LB/RB in the HUD (cosmetic)

### Optional automated smoke (dev)

```bash
godot --path . -- --smoke
```

Expect `SMOKE_OK` after Phase 1–5 + Phase A–G + Waves 0–6 + shoot-cam + core-loop feel + AI credibility checks (pressure outlets, contest windows, GK shot-line cover).

## License

All rights reserved unless otherwise noted by the repository owner.
