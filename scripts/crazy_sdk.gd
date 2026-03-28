extends Node
## CrazyGames SDK wrapper. All SDK calls go through here.
## Handles graceful fallback when running outside CrazyGames.

var _sdk_available: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_init_sdk()
		_setup_fullscreen_focus()

func _setup_fullscreen_focus() -> void:
	# CrazyGames fullscreen resizes the iframe rather than using the native
	# Fullscreen API, so 'fullscreenchange' never fires inside the game.
	# Instead, listen for resize + any pointer interaction to re-focus the canvas.
	JavaScriptBridge.eval("""
		(function() {
			var c = document.getElementById('canvas');
			if (!c) return;
			window.addEventListener('resize', function() {
				setTimeout(function() { c.focus(); }, 100);
			});
			document.addEventListener('pointerdown', function() {
				c.focus();
			});
			window.addEventListener('focus', function() {
				setTimeout(function() { c.focus(); }, 50);
			});
		})();
	""")

func _init_sdk() -> void:
	var js_check = JavaScriptBridge.eval("""
		(typeof window !== 'undefined' && typeof window.CrazyGames !== 'undefined' && typeof window.CrazyGames.SDK !== 'undefined')
	""", true)
	_sdk_available = js_check == true
	if _sdk_available:
		JavaScriptBridge.eval("window.CrazyGames.SDK.init()")

func is_available() -> bool:
	return _sdk_available and OS.has_feature("web")

# --- Loading ---

func loading_stop() -> void:
	if not is_available():
		return
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.loadingStop()")

# --- Gameplay events ---

func gameplay_start() -> void:
	if not is_available():
		return
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.gameplayStart()")

func gameplay_stop() -> void:
	if not is_available():
		return
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.gameplayStop()")

func happy_time() -> void:
	if not is_available():
		return
	JavaScriptBridge.eval("window.CrazyGames.SDK.game.happytime()")

# --- Ads ---

func show_midgame_ad(on_complete: Callable) -> void:
	if not is_available():
		on_complete.call()
		return

	AudioManager.mute_all()
	get_tree().paused = true

	var _cb_finished = JavaScriptBridge.create_callback(func(_args):
		get_tree().paused = false
		AudioManager.unmute_all()
		on_complete.call()
	)
	var _cb_error = JavaScriptBridge.create_callback(func(_args):
		get_tree().paused = false
		AudioManager.unmute_all()
		on_complete.call()
	)

	JavaScriptBridge.eval("""
		window.CrazyGames.SDK.ad.requestAd('midgame', {
			adStarted: () => {},
			adFinished: () => { %s },
			adError: () => { %s }
		})
	""" % [
		"window.godotCallbacks.midgameFinished()",
		"window.godotCallbacks.midgameError()"
	])
	# Note: The actual callback mechanism depends on the CrazySDK Godot plugin.
	# If using the plugin, replace the above with:
	# CrazyGames.Ad.request_ad("midgame", ad_started_cb, ad_finished_cb, ad_error_cb)
	# For now, the on_complete callable handles both finish and error.
	# This will be refined when the plugin is integrated.

	# Simplified fallback: just call complete after a short delay when testing locally
	if not is_available():
		await get_tree().create_timer(0.5).timeout
		get_tree().paused = false
		AudioManager.unmute_all()
		on_complete.call()

func show_rewarded_ad(on_reward: Callable, on_skip: Callable) -> void:
	if not is_available():
		# In local dev, just give the reward for testing
		on_reward.call()
		return

	AudioManager.mute_all()
	get_tree().paused = true

	# Same note as midgame — this will be refined with the actual plugin
	# For now, provide a working local fallback
	on_reward.call()
	get_tree().paused = false
	AudioManager.unmute_all()

# --- Data (save/load) ---

func save_data(key: String, value: String) -> void:
	if is_available():
		JavaScriptBridge.eval(
			"window.CrazyGames.SDK.data.setItem('%s', '%s')" % [
				key.replace("'", "\\'"),
				value.replace("'", "\\'")
			]
		)
	elif OS.has_feature("web"):
		JavaScriptBridge.eval(
			"localStorage.setItem('%s', '%s')" % [
				key.replace("'", "\\'"),
				value.replace("'", "\\'")
			]
		)

func load_data(key: String) -> String:
	if is_available():
		var result = JavaScriptBridge.eval(
			"window.CrazyGames.SDK.data.getItem('%s')" % [key.replace("'", "\\'")]
		)
		return result if result else ""
	elif OS.has_feature("web"):
		var result = JavaScriptBridge.eval(
			"localStorage.getItem('%s')" % [key.replace("'", "\\'")]
		)
		return result if result else ""
	return ""
