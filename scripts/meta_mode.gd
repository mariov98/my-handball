extends RefCounted
class_name MetaMode
## §10.1 lite career / training / hotseat flags (sandbox).

const SAVE_PATH := "user://career_season.cfg"

enum PlayMode { FRIENDLY, SEASON, TRAINING }

static var play_mode: int = PlayMode.FRIENDLY
static var hotseat_enabled: bool = false
static var kit_variant: int = 0  # procedural visual pack index
static var season_wins: int = 0
static var season_draws: int = 0
static var season_losses: int = 0
static var season_played: int = 0
static var training_shots: int = 0
static var training_goals: int = 0


static func load_career() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	season_wins = int(cfg.get_value("season", "wins", 0))
	season_draws = int(cfg.get_value("season", "draws", 0))
	season_losses = int(cfg.get_value("season", "losses", 0))
	season_played = int(cfg.get_value("season", "played", 0))
	kit_variant = int(cfg.get_value("visual", "kit_variant", 0))
	hotseat_enabled = bool(cfg.get_value("play", "hotseat", false))
	play_mode = int(cfg.get_value("play", "mode", PlayMode.FRIENDLY))


static func save_career() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("season", "wins", season_wins)
	cfg.set_value("season", "draws", season_draws)
	cfg.set_value("season", "losses", season_losses)
	cfg.set_value("season", "played", season_played)
	cfg.set_value("visual", "kit_variant", kit_variant)
	cfg.set_value("play", "hotseat", hotseat_enabled)
	cfg.set_value("play", "mode", play_mode)
	cfg.save(SAVE_PATH)


static func record_match_result(home: int, away: int) -> void:
	if play_mode != PlayMode.SEASON:
		return
	season_played += 1
	if home > away:
		season_wins += 1
	elif home < away:
		season_losses += 1
	else:
		season_draws += 1
	save_career()


static func season_summary() -> String:
	return "Season %dW-%dD-%dL (%d played)" % [
		season_wins, season_draws, season_losses, season_played
	]


static func mode_label() -> String:
	match play_mode:
		PlayMode.SEASON:
			return "Season"
		PlayMode.TRAINING:
			return "Training"
		_:
			return "Friendly"


static func cycle_play_mode() -> void:
	play_mode = (play_mode + 1) % 3
	save_career()


static func toggle_hotseat() -> void:
	hotseat_enabled = not hotseat_enabled
	save_career()


static func cycle_kit_variant() -> void:
	kit_variant = (kit_variant + 1) % 3
	save_career()


## Procedural kit tint for visual pack substitute (§10.2 authored art).
static func kit_tint_for_team(team_id: int) -> Color:
	match kit_variant:
		1:
			return Color(0.18, 0.55, 0.48) if team_id == 0 else Color(0.95, 0.55, 0.18)
		2:
			return Color(0.08, 0.18, 0.38) if team_id == 0 else Color(0.55, 0.08, 0.28)
		_:
			return Color(0.12, 0.42, 0.92) if team_id == 0 else Color(0.92, 0.16, 0.14)
