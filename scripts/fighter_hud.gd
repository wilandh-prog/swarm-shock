extends Control
## F-16 style HUD overlay. Draws speed/altitude tapes, heading compass,
## pitch ladder, flight path marker, lock indicator, and G-meter via _draw().

var player: CharacterBody3D = null

# Colors
const HUD_GREEN := Color(0.0, 1.0, 0.255, 0.9)
const HUD_GREEN_DIM := Color(0.0, 1.0, 0.255, 0.4)
const HUD_BG := Color(0.0, 0.05, 0.0, 0.3)

# Smoothed display values
var _smooth_speed: float = 0.0
var _smooth_alt: float = 0.0
var _smooth_g: float = 1.0

func _process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	_smooth_speed = lerpf(_smooth_speed, player._current_speed, 8.0 * delta)
	_smooth_alt = lerpf(_smooth_alt, player.global_position.y, 8.0 * delta)
	# G-force approximation from turn rate and speed
	var turn_frac: float = absf(player._turn_speed) / player.MAX_TURN_RATE
	var speed_frac: float = player._current_speed / player.move_speed
	_smooth_g = lerpf(_smooth_g, 1.0 + 7.0 * turn_frac * speed_frac, 5.0 * delta)
	queue_redraw()

func _draw() -> void:
	if not player or not is_instance_valid(player):
		return
	var ss := get_viewport_rect().size
	_draw_heading_tape(ss)
	_draw_speed_tape(ss)
	_draw_altitude_tape(ss)
	_draw_pitch_ladder(ss)
	_draw_flight_path_marker(ss)
	_draw_center_reticle(ss)
	_draw_lock_reticle(ss)
	_draw_missile_warning(ss)
	_draw_g_meter(ss)
	_draw_flare_status(ss)
	_draw_radar(ss)

# --- Heading tape (top center) ---

func _draw_heading_tape(ss: Vector2) -> void:
	var cx: float = ss.x * 0.5
	var y: float = 78.0
	var half_w: float = 200.0
	var font := ThemeDB.fallback_font
	if not font:
		return

	draw_rect(Rect2(cx - half_w, y - 18, half_w * 2.0, 42), HUD_BG)

	# Use raw (unwrapped) heading for smooth scrolling at 0/360 boundary
	var raw_deg: float = rad_to_deg(player._heading)
	var ppd: float = 3.0
	var base: int = int(floor(raw_deg))
	var frac: float = raw_deg - float(base)

	var compass := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

	for i in range(-35, 36):
		var tick_raw: int = base + i
		var td: int = posmod(tick_raw, 360)
		var xp: float = cx + float(i) * ppd - frac * ppd
		if xp < cx - half_w or xp > cx + half_w:
			continue
		if compass.has(td):
			draw_line(Vector2(xp, y + 4), Vector2(xp, y + 18), HUD_GREEN, 1.5)
			draw_string(font, Vector2(xp - 10, y - 4), compass[td], HORIZONTAL_ALIGNMENT_CENTER, 20, 13, HUD_GREEN)
		elif td % 10 == 0:
			draw_line(Vector2(xp, y + 6), Vector2(xp, y + 18), HUD_GREEN, 1.5)
			draw_string(font, Vector2(xp - 15, y - 4), "%03d" % td, HORIZONTAL_ALIGNMENT_CENTER, 30, 11, HUD_GREEN_DIM)
		elif td % 5 == 0:
			draw_line(Vector2(xp, y + 12), Vector2(xp, y + 18), HUD_GREEN_DIM, 1.0)

	# Center caret
	draw_line(Vector2(cx, y + 20), Vector2(cx - 5, y + 26), HUD_GREEN, 1.5)
	draw_line(Vector2(cx, y + 20), Vector2(cx + 5, y + 26), HUD_GREEN, 1.5)

	# Heading readout box
	var bx: float = cx - 22.0
	var by: float = y - 18.0
	draw_rect(Rect2(bx, by, 44, 18), Color(0, 0.03, 0, 0.85))
	draw_rect(Rect2(bx, by, 44, 18), HUD_GREEN, false, 1.5)
	var disp_hdg: int = posmod(int(round(raw_deg)), 360)
	draw_string(font, Vector2(bx + 2, by + 14), "%03d" % disp_hdg, HORIZONTAL_ALIGNMENT_CENTER, 40, 13, HUD_GREEN)

# --- Speed tape (left side) ---

func _draw_speed_tape(ss: Vector2) -> void:
	var x: float = 110.0
	var cy: float = ss.y * 0.5
	var half_h: float = 140.0
	var font := ThemeDB.fallback_font
	if not font:
		return

	# Background + right border
	draw_rect(Rect2(x - 50, cy - half_h, 78, half_h * 2.0), HUD_BG)
	draw_line(Vector2(x + 28, cy - half_h), Vector2(x + 28, cy + half_h), HUD_GREEN, 1.0)

	# Speed in display units (game speed / 100)
	var spd: float = _smooth_speed * 0.01
	var ppu: float = 4.0
	var base: int = int(floor(spd))
	var frac: float = spd - float(base)

	for i in range(-20, 21):
		var tick: int = base + i
		if tick < 0:
			continue
		var yp: float = cy - float(i) * ppu + frac * ppu
		if yp < cy - half_h or yp > cy + half_h:
			continue
		if tick % 5 == 0:
			draw_line(Vector2(x + 8, yp), Vector2(x + 28, yp), HUD_GREEN, 1.5)
			draw_string(font, Vector2(x - 45, yp + 5), str(tick), HORIZONTAL_ALIGNMENT_RIGHT, 50, 13, HUD_GREEN)
		else:
			draw_line(Vector2(x + 18, yp), Vector2(x + 28, yp), HUD_GREEN_DIM, 1.0)

	# Current value box
	draw_rect(Rect2(x - 42, cy - 11, 65, 22), Color(0, 0.03, 0, 0.85))
	draw_rect(Rect2(x - 42, cy - 11, 65, 22), HUD_GREEN, false, 1.5)
	draw_string(font, Vector2(x - 38, cy + 5), "%d" % int(spd), HORIZONTAL_ALIGNMENT_LEFT, 58, 15, HUD_GREEN)

	# Label
	draw_string(font, Vector2(x - 20, cy - half_h - 5), "SPD", HORIZONTAL_ALIGNMENT_CENTER, 50, 11, HUD_GREEN_DIM)

# --- Altitude tape (right side) ---

func _draw_altitude_tape(ss: Vector2) -> void:
	var x: float = ss.x - 110.0
	var cy: float = ss.y * 0.5
	var half_h: float = 140.0
	var font := ThemeDB.fallback_font
	if not font:
		return

	# Background + left border
	draw_rect(Rect2(x - 28, cy - half_h, 78, half_h * 2.0), HUD_BG)
	draw_line(Vector2(x - 28, cy - half_h), Vector2(x - 28, cy + half_h), HUD_GREEN, 1.0)

	var alt: float = _smooth_alt
	var step: float = 100.0
	var ppstep: float = 15.0
	var base: int = int(floor(alt / step))
	var frac: float = alt / step - float(base)

	for i in range(-12, 13):
		var tick: int = base + i
		var tick_val: int = tick * int(step)
		var yp: float = cy - float(i) * ppstep + frac * ppstep
		if yp < cy - half_h or yp > cy + half_h:
			continue
		if tick_val % 500 == 0:
			draw_line(Vector2(x - 28, yp), Vector2(x - 8, yp), HUD_GREEN, 1.5)
			draw_string(font, Vector2(x - 3, yp + 5), str(tick_val), HORIZONTAL_ALIGNMENT_LEFT, 55, 13, HUD_GREEN)
		elif tick_val % 100 == 0:
			draw_line(Vector2(x - 28, yp), Vector2(x - 18, yp), HUD_GREEN_DIM, 1.0)

	# Current value box
	draw_rect(Rect2(x - 22, cy - 11, 65, 22), Color(0, 0.03, 0, 0.85))
	draw_rect(Rect2(x - 22, cy - 11, 65, 22), HUD_GREEN, false, 1.5)
	draw_string(font, Vector2(x - 18, cy + 5), "%d" % int(alt), HORIZONTAL_ALIGNMENT_LEFT, 58, 15, HUD_GREEN)

	# Label
	draw_string(font, Vector2(x - 5, cy - half_h - 5), "ALT", HORIZONTAL_ALIGNMENT_CENTER, 50, 11, HUD_GREEN_DIM)

# --- Pitch ladder (center) ---

func _draw_pitch_ladder(ss: Vector2) -> void:
	var cx: float = ss.x * 0.5
	var cy: float = ss.y * 0.5

	var vel := player.velocity
	var horiz: float = Vector2(vel.x, vel.z).length()
	var pitch_deg: float = 0.0
	if horiz > 10.0:
		pitch_deg = rad_to_deg(atan2(vel.y, horiz))

	var bank: float = player._bank_angle
	var ppd: float = 5.0
	var half_w: float = 80.0
	var gap: float = 30.0
	var font := ThemeDB.fallback_font

	# Horizon line (pitch = 0)
	var h_off: float = pitch_deg * ppd
	var hl1 := _rot(Vector2(cx - half_w - 30, cy + h_off), cx, cy, bank)
	var hl2 := _rot(Vector2(cx - gap - 10, cy + h_off), cx, cy, bank)
	var hr1 := _rot(Vector2(cx + gap + 10, cy + h_off), cx, cy, bank)
	var hr2 := _rot(Vector2(cx + half_w + 30, cy + h_off), cx, cy, bank)
	draw_line(hl1, hl2, HUD_GREEN, 1.5)
	draw_line(hr1, hr2, HUD_GREEN, 1.5)

	# Pitch lines every 5 degrees
	for p in range(-20, 25, 5):
		if p == 0:
			continue
		var y_off: float = -(float(p) - pitch_deg) * ppd
		var l1 := _rot(Vector2(cx - half_w, cy + y_off), cx, cy, bank)
		var l2 := _rot(Vector2(cx - gap, cy + y_off), cx, cy, bank)
		var r1 := _rot(Vector2(cx + gap, cy + y_off), cx, cy, bank)
		var r2 := _rot(Vector2(cx + half_w, cy + y_off), cx, cy, bank)

		if p > 0:
			draw_line(l1, l2, HUD_GREEN_DIM, 1.0)
			draw_line(r1, r2, HUD_GREEN_DIM, 1.0)
		else:
			# Dashed lines for negative pitch
			_dashed(l1, l2, HUD_GREEN_DIM, 1.0, 6.0)
			_dashed(r1, r2, HUD_GREEN_DIM, 1.0, 6.0)

		if font:
			var lp := _rot(Vector2(cx - half_w - 28, cy + y_off + 4), cx, cy, bank)
			draw_string(font, lp, str(p), HORIZONTAL_ALIGNMENT_RIGHT, 25, 10, HUD_GREEN_DIM)

# --- Flight path marker (velocity vector) ---

func _draw_flight_path_marker(ss: Vector2) -> void:
	var cx: float = ss.x * 0.5
	var cy: float = ss.y * 0.5
	var vel := player.velocity
	var horiz: float = Vector2(vel.x, vel.z).length()
	if horiz < 10.0:
		return

	var vel_hdg: float = atan2(vel.x, -vel.z)
	var hdg_diff: float = vel_hdg - player._heading
	hdg_diff = fposmod(hdg_diff + PI, TAU) - PI  # normalize to [-PI, PI]
	var pitch: float = atan2(vel.y, horiz)

	var mx: float = cx + hdg_diff * 120.0
	var my: float = cy - pitch * 120.0
	var r: float = 7.0

	# Circle with wings and fin
	draw_arc(Vector2(mx, my), r, 0, TAU, 24, HUD_GREEN, 1.5)
	draw_line(Vector2(mx - r - 10, my), Vector2(mx - r, my), HUD_GREEN, 1.5)
	draw_line(Vector2(mx + r, my), Vector2(mx + r + 10, my), HUD_GREEN, 1.5)
	draw_line(Vector2(mx, my - r), Vector2(mx, my - r - 7), HUD_GREEN, 1.5)

# --- Center reticle ---

func _draw_center_reticle(ss: Vector2) -> void:
	var cx: float = ss.x * 0.5
	var cy: float = ss.y * 0.5
	var s: float = 14.0
	var g: float = 7.0
	draw_line(Vector2(cx - s, cy), Vector2(cx - g, cy), HUD_GREEN, 1.5)
	draw_line(Vector2(cx + g, cy), Vector2(cx + s, cy), HUD_GREEN, 1.5)
	draw_line(Vector2(cx, cy - s), Vector2(cx, cy - g), HUD_GREEN, 1.5)
	draw_line(Vector2(cx, cy + g), Vector2(cx, cy + s), HUD_GREEN, 1.5)

# --- Lock reticle (progressive circle) ---

func _draw_lock_reticle(ss: Vector2) -> void:
	if not player.weapon_manager:
		return
	var wm = player.weapon_manager
	if not is_instance_valid(wm.tracking_target):
		return
	var tgt: Node3D = wm.tracking_target

	var cam := get_viewport().get_camera_3d()
	if not cam or cam.is_position_behind(tgt.global_position):
		return

	var pos: Vector2 = cam.unproject_position(tgt.global_position)
	var progress: float = wm.lock_progress
	var is_locked: bool = wm.locked_target != null and is_instance_valid(wm.locked_target)

	# Circle shrinks from 80px to 18px
	var radius: float = lerpf(80.0, 18.0, progress)

	var color: Color = HUD_GREEN
	if is_locked:
		var flash: float = fmod(Time.get_ticks_msec() * 0.001, 0.3)
		color = HUD_GREEN if flash < 0.2 else Color(0.0, 1.0, 0.255, 0.5)

	# Main circle
	draw_arc(pos, radius, 0, TAU, 48, color, 2.0)

	# 4 tick marks pointing inward
	var tick: float = 12.0
	draw_line(pos + Vector2(0, -radius - tick), pos + Vector2(0, -radius), color, 1.5)
	draw_line(pos + Vector2(0, radius), pos + Vector2(0, radius + tick), color, 1.5)
	draw_line(pos + Vector2(-radius - tick, 0), pos + Vector2(-radius, 0), color, 1.5)
	draw_line(pos + Vector2(radius, 0), pos + Vector2(radius + tick, 0), color, 1.5)

	var font := ThemeDB.fallback_font
	if not font:
		return

	var dist: float = player.global_position.distance_to(tgt.global_position)
	draw_string(font, Vector2(pos.x - 30, pos.y + radius + 30), "%dM" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, color)

	if is_locked:
		draw_string(font, Vector2(pos.x - 25, pos.y + radius + 16), "LOCK", HORIZONTAL_ALIGNMENT_CENTER, 50, 16, color)

# --- Incoming missile warning ---

const WARN_RED := Color(1.0, 0.15, 0.1, 0.95)
const WARN_RED_DIM := Color(1.0, 0.15, 0.1, 0.5)

func _draw_missile_warning(ss: Vector2) -> void:
	var missiles := get_tree().get_nodes_in_group("enemy_projectile")
	if missiles.is_empty():
		return

	# Find nearest incoming missile
	var nearest_dist: float = INF
	for m in missiles:
		if not is_instance_valid(m):
			continue
		var d: float = player.global_position.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d

	var font := ThemeDB.fallback_font
	if not font:
		return

	var cx: float = ss.x * 0.5
	var y: float = ss.y - 120.0

	# Fast flash (3.3 Hz)
	var t: float = fmod(Time.get_ticks_msec() * 0.001, 0.3)
	var visible_phase: bool = t < 0.2

	# Warning box background
	var box_w: float = 340.0
	var box_h: float = 50.0
	var box_rect := Rect2(cx - box_w * 0.5, y - box_h * 0.5, box_w, box_h)
	draw_rect(box_rect, Color(0.15, 0.0, 0.0, 0.7))
	draw_rect(box_rect, WARN_RED if visible_phase else WARN_RED_DIM, false, 2.0)

	# Big flashing text
	if visible_phase:
		draw_string(font, Vector2(cx - 155, y + 8), "INCOMING MISSILE", HORIZONTAL_ALIGNMENT_CENTER, 310, 24, WARN_RED)
	else:
		draw_string(font, Vector2(cx - 155, y + 8), "INCOMING MISSILE", HORIZONTAL_ALIGNMENT_CENTER, 310, 24, WARN_RED_DIM)

	# Count + distance
	var count: int = missiles.size()
	var info: String = "x%d  %dM" % [count, int(nearest_dist)]
	draw_string(font, Vector2(cx - 60, y + 28), info, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, WARN_RED)

# --- G-meter ---

func _draw_g_meter(ss: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var x: float = 75.0
	var y: float = ss.y * 0.5 + 165.0
	draw_string(font, Vector2(x, y), "G", HORIZONTAL_ALIGNMENT_LEFT, 15, 11, HUD_GREEN_DIM)
	var g_color: Color = HUD_GREEN
	if _smooth_g > 5.0:
		g_color = Color(1.0, 0.8, 0.0, 0.9)
	if _smooth_g > 7.0:
		g_color = Color(1.0, 0.3, 0.2, 0.9)
	draw_string(font, Vector2(x + 15, y), "%.1f" % _smooth_g, HORIZONTAL_ALIGNMENT_LEFT, 40, 15, g_color)

# --- Flare status ---

func _draw_flare_status(ss: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var x: float = 75.0
	var y: float = ss.y * 0.5 + 185.0
	if player._flare_cooldown <= 0.0:
		draw_string(font, Vector2(x, y), "FLARE RDY", HORIZONTAL_ALIGNMENT_LEFT, 80, 11, HUD_GREEN)
	else:
		draw_string(font, Vector2(x, y), "FLARE %.1f" % player._flare_cooldown, HORIZONTAL_ALIGNMENT_LEFT, 80, 11, HUD_GREEN_DIM)

# --- Radar (bottom-left) ---

const RADAR_RADIUS: float = 70.0
const RADAR_RANGE: float = 3000.0

func _draw_radar(ss: Vector2) -> void:
	var cx: float = 90.0
	var cy: float = ss.y - 90.0

	# Background circle
	draw_circle(Vector2(cx, cy), RADAR_RADIUS + 2, Color(0.0, 0.04, 0.0, 0.5))
	draw_arc(Vector2(cx, cy), RADAR_RADIUS, 0, TAU, 48, HUD_GREEN, 1.5)

	# Range rings
	draw_arc(Vector2(cx, cy), RADAR_RADIUS * 0.5, 0, TAU, 32, HUD_GREEN_DIM, 0.5)

	# Cross lines
	draw_line(Vector2(cx - RADAR_RADIUS, cy), Vector2(cx + RADAR_RADIUS, cy), HUD_GREEN_DIM, 0.5)
	draw_line(Vector2(cx, cy - RADAR_RADIUS), Vector2(cx, cy + RADAR_RADIUS), HUD_GREEN_DIM, 0.5)

	# Player heading line
	var hdg: float = player._heading
	var fwd_x: float = sin(hdg) * RADAR_RADIUS * 0.3
	var fwd_y: float = -cos(hdg) * RADAR_RADIUS * 0.3
	draw_line(Vector2(cx, cy), Vector2(cx + fwd_x, cy + fwd_y), HUD_GREEN, 1.5)

	# Player dot
	draw_circle(Vector2(cx, cy), 3.0, HUD_GREEN)

	# Enemy blips
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var rel: Vector3 = enemy.global_position - player.global_position
		var dist: float = Vector2(rel.x, rel.z).length()
		if dist > RADAR_RANGE:
			continue
		var radar_x: float = rel.x / RADAR_RANGE * RADAR_RADIUS
		var radar_y: float = rel.z / RADAR_RANGE * RADAR_RADIUS
		# Clamp to radar circle
		var blip := Vector2(cx + radar_x, cy + radar_y)
		if blip.distance_to(Vector2(cx, cy)) > RADAR_RADIUS:
			continue
		draw_rect(Rect2(blip.x - 2, blip.y - 2, 4, 4), WARN_RED)

	# Incoming missiles
	var missiles := get_tree().get_nodes_in_group("enemy_projectile")
	for m in missiles:
		if not is_instance_valid(m):
			continue
		var rel: Vector3 = m.global_position - player.global_position
		var radar_x: float = rel.x / RADAR_RANGE * RADAR_RADIUS
		var radar_y: float = rel.z / RADAR_RANGE * RADAR_RADIUS
		var blip := Vector2(cx + radar_x, cy + radar_y)
		if blip.distance_to(Vector2(cx, cy)) > RADAR_RADIUS:
			continue
		# Flashing triangle for missiles
		var flash: float = fmod(Time.get_ticks_msec() * 0.001, 0.3)
		if flash < 0.2:
			var tri_size: float = 4.0
			draw_line(Vector2(blip.x, blip.y - tri_size), Vector2(blip.x - tri_size, blip.y + tri_size), WARN_RED, 1.5)
			draw_line(Vector2(blip.x, blip.y - tri_size), Vector2(blip.x + tri_size, blip.y + tri_size), WARN_RED, 1.5)
			draw_line(Vector2(blip.x - tri_size, blip.y + tri_size), Vector2(blip.x + tri_size, blip.y + tri_size), WARN_RED, 1.5)

	# Label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(cx - 10, cy - RADAR_RADIUS - 5), "RDR", HORIZONTAL_ALIGNMENT_CENTER, 30, 11, HUD_GREEN_DIM)

# --- Helpers ---

func _rot(p: Vector2, cx: float, cy: float, angle: float) -> Vector2:
	var o := p - Vector2(cx, cy)
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector2(cx + o.x * c - o.y * s, cy + o.x * s + o.y * c)

func _dashed(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length: float = from.distance_to(to)
	if length < 1.0:
		return
	var dir: Vector2 = (to - from) / length
	var pos: float = 0.0
	var on: bool = true
	while pos < length:
		var next: float = minf(pos + dash, length)
		if on:
			draw_line(from + dir * pos, from + dir * next, color, width)
		pos = next
		on = not on
