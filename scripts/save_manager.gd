extends Node
## Handles saving and loading persistent game data.
## Uses CrazySdk Data module on web, file system locally.

const SAVE_KEY: String = "navy_gun_save"
const SAVE_PATH: String = "user://save_data.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_all()

# --- Save ---

func save_all() -> void:
	var data := {
		"xp_total": GameManager.xp_total,
		"unlocked_characters": GameManager.unlocked_characters,
		"upgrade_levels": GameManager.upgrade_levels,
		"selected_character": GameManager.selected_character,
		"best_kills": GameManager.best_kills,
		"best_time": GameManager.best_time,
		"best_level": GameManager.best_level,
		"best_xp": GameManager.best_xp,
		"best_wave": GameManager.best_wave,
	}
	var json_string := JSON.stringify(data)

	if OS.has_feature("web"):
		CrazySdk.save_data(SAVE_KEY, json_string)
	else:
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(json_string)
			file.close()

# --- Load ---

func load_all() -> void:
	var json_string: String = ""

	if OS.has_feature("web"):
		json_string = CrazySdk.load_data(SAVE_KEY)
	else:
		if FileAccess.file_exists(SAVE_PATH):
			var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
			if file:
				json_string = file.get_as_text()
				file.close()

	if json_string.is_empty():
		return

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_warning("SaveManager: Failed to parse save data")
		return

	var data: Dictionary = json.data
	if data.has("xp_total"):
		GameManager.xp_total = int(data["xp_total"])
	elif data.has("volts"):
		GameManager.xp_total = int(data["volts"])
	if data.has("unlocked_characters"):
		GameManager.unlocked_characters.assign(data["unlocked_characters"])
	if data.has("upgrade_levels"):
		for key in data["upgrade_levels"]:
			GameManager.upgrade_levels[key] = int(data["upgrade_levels"][key])
	if data.has("selected_character"):
		GameManager.selected_character = str(data["selected_character"])
	if data.has("best_kills"):
		GameManager.best_kills = int(data["best_kills"])
	if data.has("best_time"):
		GameManager.best_time = float(data["best_time"])
	if data.has("best_level"):
		GameManager.best_level = int(data["best_level"])
	if data.has("best_xp"):
		GameManager.best_xp = int(data["best_xp"])
	if data.has("best_wave"):
		GameManager.best_wave = int(data["best_wave"])
