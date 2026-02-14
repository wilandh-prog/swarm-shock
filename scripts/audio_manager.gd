extends Node
## Global audio manager. Handles mute/unmute for ads and SDK settings.

var _muted: bool = false
var _master_bus: int = 0

# Audio players managed centrally
var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX_PLAYERS: int = 8

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_master_bus = AudioServer.get_bus_index("Master")
	_setup_players()

func _setup_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -6.0
	add_child(_music_player)

	for i in MAX_SFX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_sfx_players.append(player)

# --- Mute control ---

func mute_all() -> void:
	_muted = true
	AudioServer.set_bus_mute(_master_bus, true)

func unmute_all() -> void:
	_muted = false
	AudioServer.set_bus_mute(_master_bus, false)

func is_muted() -> bool:
	return _muted

# --- Music ---

func play_music(stream: AudioStream) -> void:
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

# --- SFX ---

func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	for player in _sfx_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.play()
			return
	# All players busy — use the first one (oldest sound gets cut)
	_sfx_players[0].stream = stream
	_sfx_players[0].volume_db = volume_db
	_sfx_players[0].play()
