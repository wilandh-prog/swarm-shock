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

# AWACS radio
var awacs_text: String = ""
var _awacs_alpha: float = 0.0
var wave_current: int = 0
var wave_total: int = 0
var speed_display_divisor: float = 1.0

# Landing guidance
var landing_active: bool = false
var landing_carrier: Node3D = null
var landing_heading: float = 0.0
var landing_deck_y: float = 70.0
var _landing_debug_printed: bool = false

func _process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	_smooth_speed = lerpf(_smooth_speed, player._current_speed, 8.0 * delta)
	_smooth_alt = lerpf(_smooth_alt, player.global_position.y, 8.0 * delta)
	# G-force approximation from turn rate and speed
	var turn_frac: float = absf(player._turn_speed) / player.MAX_TURN_RATE
	var speed_frac: float = player._current_speed / player.move_speed
	_smooth_g = lerpf(_smooth_g, 1.0 + 7.0 * turn_frac * speed_frac, 5.0 * delta)
	# AWACS fade out
	if awacs_text == "":
		_awacs_alpha = move_toward(_awacs_alpha, 0.0, 2.0 * delta)
	else:
		_awacs_alpha = move_toward(_awacs_alpha, 1.0, 4.0 * delta)
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
	_draw_gun_aimpoint(ss)
	_draw_lock_reticle(ss)
	_draw_missile_warning(ss)
	_draw_g_meter(ss)
	_draw_flare_status(ss)
	_draw_radar(ss)
	_draw_speed_lines(ss)
	_draw_awacs_radio(ss)
	_draw_wave_indicator(ss)
	if landing_active:
		_draw_landing_guidance(ss)

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

	# Speed in knots (game speed × 2.5 so cruise ~500kt), adjusted for landing boost
	var spd: float = _smooth_speed / speed_display_divisor * 2.5
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

# --- Gun aimpoint (bullet impact point) ---

func _draw_gun_aimpoint(ss: Vector2) -> void:
	if not player or not player.weapon_manager:
		return
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	var fwd := Vector3(sin(player._heading), 0.0, -cos(player._heading))
	var bullet_speed: float = player.weapon_manager.gun_speed

	# Find nearest enemy to determine range for the pipper
	var target_dist: float = 1500.0  # default range if no enemy
	var best_enemy: Node3D = null
	var best_dist: float = 2500.0

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var d: float = player.global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best_enemy = enemy

	if best_enemy:
		target_dist = best_dist

	# Bullet time of flight to that range
	var tof: float = target_dist / bullet_speed

	# Where the bullet will be: starts at player pos, moves in player forward dir
	# at bullet_speed for tof seconds
	var impact_pos: Vector3 = player.global_position + fwd * bullet_speed * tof

	if cam.is_position_behind(impact_pos):
		return

	var pipper: Vector2 = cam.unproject_position(impact_pos)
	pipper.x = clampf(pipper.x, 30.0, ss.x - 30.0)
	pipper.y = clampf(pipper.y, 30.0, ss.y - 30.0)

	# Draw bullet trail dots at multiple ranges
	var trail_dists: Array[float] = [200.0, 400.0, 600.0, 900.0, 1200.0]
	for td in trail_dists:
		if td >= target_dist:
			break
		var trail_pos: Vector3 = player.global_position + fwd * td
		if cam.is_position_behind(trail_pos):
			continue
		var tp: Vector2 = cam.unproject_position(trail_pos)
		draw_circle(tp, 2.0, HUD_GREEN_DIM)

	# Draw pipper — where bullets arrive at target range
	var r: float = 14.0
	draw_arc(pipper, r, 0, TAU, 32, HUD_GREEN, 2.0)
	draw_circle(pipper, 3.0, HUD_GREEN)

	# Ticks
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2(cos(angle), sin(angle))
		draw_line(pipper + d * r, pipper + d * (r + 6.0), HUD_GREEN, 1.5)

	# Range label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(pipper.x - 25, pipper.y + r + 16), "%dM" % int(target_dist), HORIZONTAL_ALIGNMENT_CENTER, 50, 11, HUD_GREEN_DIM)

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

	# Player heading indicator (always points up)
	draw_line(Vector2(cx, cy), Vector2(cx, cy - RADAR_RADIUS * 0.3), HUD_GREEN, 1.5)

	# Player dot
	draw_circle(Vector2(cx, cy), 3.0, HUD_GREEN)

	var hdg: float = player._heading

	# Enemy blips (rotated by heading so forward = up)
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var rel: Vector3 = enemy.global_position - player.global_position
		var dist: float = Vector2(rel.x, rel.z).length()
		if dist > RADAR_RANGE:
			continue
		var blip := _radar_blip(rel, hdg, cx, cy)
		if blip.distance_to(Vector2(cx, cy)) > RADAR_RADIUS:
			continue
		draw_rect(Rect2(blip.x - 2, blip.y - 2, 4, 4), WARN_RED)

	# Incoming missiles
	var missiles := get_tree().get_nodes_in_group("enemy_projectile")
	for m in missiles:
		if not is_instance_valid(m):
			continue
		var rel: Vector3 = m.global_position - player.global_position
		var blip := _radar_blip(rel, hdg, cx, cy)
		if blip.distance_to(Vector2(cx, cy)) > RADAR_RADIUS:
			continue
		# Flashing triangle for missiles
		var flash: float = fmod(Time.get_ticks_msec() * 0.001, 0.3)
		if flash < 0.2:
			var tri_size: float = 4.0
			draw_line(Vector2(blip.x, blip.y - tri_size), Vector2(blip.x - tri_size, blip.y + tri_size), WARN_RED, 1.5)
			draw_line(Vector2(blip.x, blip.y - tri_size), Vector2(blip.x + tri_size, blip.y + tri_size), WARN_RED, 1.5)
			draw_line(Vector2(blip.x - tri_size, blip.y + tri_size), Vector2(blip.x + tri_size, blip.y + tri_size), WARN_RED, 1.5)

	# Carrier blip (green square)
	if landing_active and landing_carrier and is_instance_valid(landing_carrier):
		var crel: Vector3 = landing_carrier.global_position - player.global_position
		var cblip := _radar_blip(crel, hdg, cx, cy)
		if cblip.distance_to(Vector2(cx, cy)) <= RADAR_RADIUS:
			draw_rect(Rect2(cblip.x - 5, cblip.y - 5, 10, 10), HUD_GREEN)

	# Label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(cx - 10, cy - RADAR_RADIUS - 5), "RDR", HORIZONTAL_ALIGNMENT_CENTER, 30, 11, HUD_GREEN_DIM)

# --- AWACS radio (top center message) ---

func _draw_awacs_radio(ss: Vector2) -> void:
	if _awacs_alpha < 0.01:
		return
	var font := ThemeDB.fallback_font
	if not font:
		return
	var cx: float = ss.x * 0.5
	var y: float = ss.y * 0.15
	var text: String = ">> " + awacs_text
	var box_w: float = maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x + 40.0, 280.0)
	var box_h: float = 36.0
	var box_rect := Rect2(cx - box_w * 0.5, y - box_h * 0.5, box_w, box_h)
	# Dark background
	draw_rect(box_rect, Color(0.0, 0.04, 0.0, 0.7 * _awacs_alpha))
	# Green border
	draw_rect(box_rect, Color(0.0, 1.0, 0.255, 0.6 * _awacs_alpha), false, 1.5)
	# Text
	draw_string(font, Vector2(cx - box_w * 0.5 + 12, y + 6), text, HORIZONTAL_ALIGNMENT_CENTER, box_w - 24, 18, Color(0.0, 1.0, 0.255, 0.95 * _awacs_alpha))

# --- Wave indicator (top right) ---

func _draw_wave_indicator(ss: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var x: float = ss.x - 130.0
	var y: float = 30.0
	var text: String
	if wave_total <= 0:
		text = "TUTORIAL"
	else:
		text = "WAVE %d/%d" % [wave_current, wave_total]
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_RIGHT, 120, 14, HUD_GREEN_DIM)

# --- Landing guidance ---

const HUD_YELLOW := Color(1.0, 0.8, 0.2, 0.9)
const HUD_ORANGE := Color(1.0, 0.5, 0.2, 0.9)

func start_landing(carrier: Node3D, heading: float, deck_y: float) -> void:
	landing_active = true
	landing_carrier = carrier
	landing_heading = heading
	landing_deck_y = deck_y
	print("Fighter HUD: landing mode ON, heading=", rad_to_deg(heading))

func _draw_landing_guidance(ss: Vector2) -> void:
	if not player or not landing_carrier:
		return
	var font := ThemeDB.fallback_font
	if not font:
		return

	if not _landing_debug_printed:
		_landing_debug_printed = true
		print("Landing guidance drawing! Speed=", player._current_speed, " Carrier=", landing_carrier.global_position)

	var to_carrier: Vector3 = landing_carrier.global_position - player.global_position
	var dist_horiz: float = Vector2(to_carrier.x, to_carrier.z).length()
	var alt_diff: float = player.global_position.y - landing_deck_y
	var heading_diff: float = fposmod(player._heading - landing_heading + PI, TAU) - PI

	var commands: Array[Dictionary] = []

	# --- Lateral lineup (offset to port to avoid island/tower on starboard) ---
	var lateral: float = _lateral_offset(to_carrier) - 150.0  # guide 150 units port of centerline
	if absf(lateral) > 400.0:
		var dir_txt: String = "RIGHT [D]" if lateral > 0 else "LEFT [A]"
		commands.append({"text": "LINEUP %s" % dir_txt, "color": WARN_RED})
	elif absf(lateral) > 100.0:
		var dir_txt: String = "RIGHT [D]" if lateral > 0 else "LEFT [A]"
		commands.append({"text": "CORRECT %s" % dir_txt, "color": HUD_ORANGE})
	elif absf(lateral) > 30.0:
		var dir_txt: String = "NUDGE RIGHT [D]" if lateral > 0 else "NUDGE LEFT [A]"
		commands.append({"text": dir_txt, "color": HUD_YELLOW})
	else:
		commands.append({"text": "ON CENTERLINE", "color": HUD_GREEN})

	# --- Heading ---
	if absf(heading_diff) > 0.1:
		var dir_txt: String = "LEFT [A]" if heading_diff > 0 else "RIGHT [D]"
		commands.append({"text": "HEADING %s" % dir_txt, "color": HUD_ORANGE})
	else:
		commands.append({"text": "HDG OK", "color": HUD_GREEN})

	# --- Speed ---
	var knots: int = int(player._current_speed * 2.5)
	var cruise: float = player.move_speed
	var landing_max: float = cruise * 0.65
	if player._current_speed >= cruise * 0.7:
		commands.append({"text": "BRAKE! [S] %dKT" % knots, "color": WARN_RED})
	elif player._current_speed >= landing_max:
		commands.append({"text": "SLOW [S] %dKT" % knots, "color": HUD_ORANGE})
	else:
		commands.append({"text": "SPD OK %dKT" % knots, "color": HUD_GREEN})

	# --- Altitude / glideslope ---
	# Shallow gradient so player must descend early in the approach
	var ideal_alt: float = landing_deck_y + dist_horiz * 0.12
	ideal_alt = maxf(ideal_alt, landing_deck_y + 10.0)
	var alt_error: float = player.global_position.y - ideal_alt
	if alt_error > 200.0:
		commands.append({"text": "DESCEND [UP]", "color": WARN_RED})
	elif alt_error > 50.0:
		commands.append({"text": "DESCEND [UP]", "color": HUD_ORANGE})
	elif alt_error < -100.0:
		commands.append({"text": "PULL UP! [DOWN]", "color": WARN_RED})
	elif alt_error < -20.0:
		commands.append({"text": "CLIMB [DOWN]", "color": HUD_YELLOW})
	else:
		commands.append({"text": "GLIDE OK", "color": HUD_GREEN})

	# Distance readout
	commands.append({"text": "DIST %dM" % int(dist_horiz), "color": HUD_GREEN_DIM})

	# Banner
	var banner: String = "FINAL APPROACH" if dist_horiz < 1500.0 else "CARRIER APPROACH"
	var banner_color: Color = HUD_YELLOW if dist_horiz < 1500.0 else HUD_GREEN

	# Draw centered below the heading tape
	var cx: float = ss.x * 0.5
	var y_start: float = ss.y * 0.28

	# Banner background
	var bw: float = 220.0
	draw_rect(Rect2(cx - bw * 0.5, y_start - 24, bw, 28), Color(0, 0.03, 0, 0.6))
	draw_rect(Rect2(cx - bw * 0.5, y_start - 24, bw, 28), banner_color * Color(1, 1, 1, 0.5), false, 1.5)
	draw_string(font, Vector2(cx - bw * 0.5 + 10, y_start - 2), banner, HORIZONTAL_ALIGNMENT_CENTER, bw - 20, 18, banner_color)

	# Commands stack
	for i in commands.size():
		var cmd: Dictionary = commands[i]
		var y_pos: float = y_start + 14 + i * 24
		draw_string(font, Vector2(cx - 90, y_pos), cmd["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 16, cmd["color"])

	# --- ILS diamond indicator (right side of screen) ---
	var ils_cx: float = ss.x - 200.0
	var ils_cy: float = ss.y * 0.5
	var ils_size: float = 80.0

	# Crosshair frame
	draw_line(Vector2(ils_cx - ils_size, ils_cy), Vector2(ils_cx + ils_size, ils_cy), HUD_GREEN_DIM, 1.0)
	draw_line(Vector2(ils_cx, ils_cy - ils_size), Vector2(ils_cx, ils_cy + ils_size), HUD_GREEN_DIM, 1.0)
	draw_rect(Rect2(ils_cx - ils_size, ils_cy - ils_size, ils_size * 2, ils_size * 2), HUD_GREEN_DIM, false, 1.0)

	# Lateral offset → horizontal diamond (clamped to box)
	var lat_norm: float = clampf(lateral / 500.0, -1.0, 1.0)
	var lat_x: float = ils_cx + lat_norm * ils_size
	_draw_diamond(Vector2(lat_x, ils_cy), 6.0, HUD_GREEN if absf(lat_norm) < 0.15 else HUD_ORANGE)

	# Glideslope offset → vertical diamond
	var gs_norm: float = clampf(alt_error / 300.0, -1.0, 1.0)
	var gs_y: float = ils_cy + gs_norm * ils_size  # positive = too high = diamond goes down... inverted
	_draw_diamond(Vector2(ils_cx, ils_cy - gs_norm * ils_size), 6.0, HUD_GREEN if absf(gs_norm) < 0.2 else HUD_ORANGE)

	# Labels
	draw_string(font, Vector2(ils_cx - 10, ils_cy - ils_size - 8), "ILS", HORIZONTAL_ALIGNMENT_CENTER, 30, 11, HUD_GREEN_DIM)
	draw_string(font, Vector2(ils_cx - ils_size - 5, ils_cy + ils_size + 14), "L", HORIZONTAL_ALIGNMENT_CENTER, 10, 11, HUD_GREEN_DIM)
	draw_string(font, Vector2(ils_cx + ils_size - 3, ils_cy + ils_size + 14), "R", HORIZONTAL_ALIGNMENT_CENTER, 10, 11, HUD_GREEN_DIM)

# --- Speed lines (radial streaks for speed sensation) ---

func _draw_speed_lines(ss: Vector2) -> void:
	if not player:
		return
	var speed_frac: float = _smooth_speed / (player.move_speed * player.MAX_SPEED_MULT)
	if speed_frac < 0.25:
		return
	var alpha: float = (speed_frac - 0.25) * 0.7
	var cx: float = ss.x * 0.5
	var cy: float = ss.y * 0.42
	var t: float = Time.get_ticks_msec() * 0.001
	var line_count: int = 28
	for i in line_count:
		var base_angle: float = float(i) / float(line_count) * TAU
		# Stagger: each line pulses at different phase
		var phase: float = sin(base_angle * 3.0 + t * 4.0) * 0.5 + 0.5
		var inner: float = 100.0 + phase * 60.0
		var outer: float = inner + speed_frac * 200.0
		var dir := Vector2(cos(base_angle), sin(base_angle))
		var a: float = alpha * phase * 0.6
		if a < 0.02:
			continue
		draw_line(
			Vector2(cx, cy) + dir * inner,
			Vector2(cx, cy) + dir * outer,
			Color(0.8, 1.0, 0.9, a),
			1.5
		)

func _lateral_offset(to_carrier: Vector3) -> float:
	var runway_dir := Vector3(sin(landing_heading), 0.0, -cos(landing_heading))
	var perp := Vector3(-runway_dir.z, 0.0, runway_dir.x)
	return to_carrier.dot(perp)

# --- Helpers ---

func _radar_blip(rel: Vector3, hdg: float, cx: float, cy: float) -> Vector2:
	# Rotate world-relative position by -heading so forward = up on radar
	var s: float = sin(-hdg)
	var c: float = cos(-hdg)
	var rx: float = rel.x * c - rel.z * s
	var ry: float = rel.x * s + rel.z * c
	return Vector2(cx + rx / RADAR_RANGE * RADAR_RADIUS, cy + ry / RADAR_RANGE * RADAR_RADIUS)

func _rot(p: Vector2, cx: float, cy: float, angle: float) -> Vector2:
	var o := p - Vector2(cx, cy)
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector2(cx + o.x * c - o.y * s, cy + o.x * s + o.y * c)

func _draw_diamond(center: Vector2, size: float, color: Color) -> void:
	var pts: PackedVector2Array = [
		center + Vector2(0, -size),
		center + Vector2(size, 0),
		center + Vector2(0, size),
		center + Vector2(-size, 0),
	]
	draw_colored_polygon(pts, color)

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
