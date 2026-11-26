extends RefCounted
class_name InputSettings
## R7.1: remappable actions + help text. Persists to user://input_remap.cfg.

const SAVE_PATH := "user://input_remap.cfg"

## Actions players may remap (keyboard event index 0 preferred).
const REMAP_ACTIONS: PackedStringArray = [
	"move_left",
	"move_right",
	"move_forward",
	"move_back",
	"jump",
	"sprint",
	"shoot",
	"pass_ball",
	"dribble",
	"lob",
	"bounce_pass",
	"dive",
	"switch_player",
	"switch_best",
	"cycle_bench",
	"confirm_sub",
	"fake_shot",
	"fake_pass",
	"fake_jab",
	"toggle_attack_shape",
	"toggle_defense_shape",
	"toggle_aim_mode",
	"camera_reset",
	"toggle_wing_cine",
	"toggle_help",
]

## Default key labels for help / README sync (prefer keyboard, then mouse, then pad).
static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return action
	var mouse_label := ""
	var pad_label := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton and mouse_label.is_empty():
			var mb := ev as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					mouse_label = "LMB"
				MOUSE_BUTTON_RIGHT:
					mouse_label = "RMB"
				MOUSE_BUTTON_MIDDLE:
					mouse_label = "MMB"
				_:
					mouse_label = "Mouse%d" % mb.button_index
		elif ev is InputEventJoypadButton and pad_label.is_empty():
			pad_label = "PadBtn%d" % (ev as InputEventJoypadButton).button_index
		elif ev is InputEventJoypadMotion and pad_label.is_empty():
			var jm := ev as InputEventJoypadMotion
			pad_label = "Axis%d%c" % [jm.axis, "+" if jm.axis_value > 0.0 else "-"]
	if not mouse_label.is_empty():
		return mouse_label
	if not pad_label.is_empty():
		return pad_label
	return "(unbound)"


static func action_has_key(action: String, code: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var kc := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			if kc == code:
				return true
	return false


static func help_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Esc / F1 — help & remap · Enter rebind · R reset selected · Esc close")
	lines.append("Move WASD · Sprint Shift · Jump Space · Dribble V · Shoot LMB/E · Pass RMB/G")
	lines.append("Lob F · Bounce B · Dive/Fake C/X · Pass fake Z · Jab N · Cycle Q · Best R")
	lines.append("Shapes 1/2 · Sub ,/. on whistle · Wing cam 4 · Camera [ ] - = PgUp/PgDn Home")
	lines.append("Mode: Esc menu → Season / Training / Hotseat · GK sub when controlling GK")
	return lines


static func load_remaps() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for action in REMAP_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if not cfg.has_section_key("keys", action):
			continue
		var code := int(cfg.get_value("keys", action, 0))
		if code == 0:
			continue
		_replace_keyboard_binding(action, code as Key)


static func save_remaps() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep other sections if any
	for action in REMAP_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var code := _first_key_code(action)
		if code != KEY_NONE:
			cfg.set_value("keys", action, int(code))
	# Headless / restricted sandboxes may lack a writable user:// — remap still applies in-memory.
	cfg.save(SAVE_PATH)


static func rebind_action_to_event(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_NONE or code == KEY_ESCAPE:
			return false
		_replace_keyboard_binding(action, code)
		save_remaps()
		return true
	if event is InputEventMouseButton:
		_replace_mouse_binding(action, (event as InputEventMouseButton).button_index)
		save_remaps()
		return true
	return false


static func reset_action_defaults(action: String) -> void:
	# Reload project defaults by removing custom key and leaving project.godot events.
	# Full reset: erase all events then callers should restart — for lite, only clear saved key.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section_key("keys", action):
		cfg.erase_section_key("keys", action)
		cfg.save(SAVE_PATH)


static func _first_key_code(action: String) -> Key:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return KEY_NONE


static func _replace_keyboard_binding(action: String, code: Key) -> void:
	var kept: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			continue
		kept.append(ev)
	InputMap.action_erase_events(action)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.keycode = code
	InputMap.action_add_event(action, key)


static func _replace_mouse_binding(action: String, button: MouseButton) -> void:
	var kept: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			continue
		# Keep gamepad; drop old mouse.
		kept.append(ev)
	InputMap.action_erase_events(action)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = true
	InputMap.action_add_event(action, mb)
