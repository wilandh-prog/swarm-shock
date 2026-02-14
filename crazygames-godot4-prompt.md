# Claude Code Prompt: Build a Successful CrazyGames Game with Godot 4

You are building a browser game using **Godot 4.x** for publication on CrazyGames.com — a platform with 30M+ monthly users. The game should have visually impressive graphics that leverage Godot's rendering capabilities. It must be technically excellent, immediately fun, and fully compliant with CrazyGames' submission requirements.

Work through the following steps sequentially. Complete each step fully before moving to the next. After each step, summarize what you decided/built and confirm before proceeding.

---

## IMPORTANT: Godot Project Structure & Claude Code Workflow

Claude Code will generate all project files as text (GDScript, .tscn scene files, .tres resource files, project.godot, export_presets.cfg). The developer (me) will then:
1. Copy the files into a Godot 4.x project
2. Import assets and verify scenes in the editor
3. Test and iterate
4. Export for web

**Claude Code's responsibilities:**
- Write all GDScript code
- Define scene structures (.tscn files in text format)
- Create shader code (.gdshader)
- Configure project settings (project.godot)
- Define export presets for web
- Provide clear instructions for what I need to do manually in the editor

**My responsibilities:**
- Open files in Godot editor
- Import/create visual assets (or use Godot's procedural generation)
- Test builds
- Export to web (single-threaded, no SharedArrayBuffer)
- Upload to CrazyGames

---

## STEP 1: Research & Game Concept Selection

**Goal:** Determine the optimal game concept — one that performs well on CrazyGames AND leverages Godot 4's visual capabilities (shaders, particles, lighting, post-processing).

### Research tasks:
1. Visit https://www.crazygames.com/hot and https://www.crazygames.com/ to identify trending games
2. Visit https://docs.crazygames.com/requirements/quality/ for quality guidelines
3. Visit https://docs.crazygames.com/requirements/gameplay/ for gameplay requirements
4. Visit https://docs.crazygames.com/requirements/technical/ for technical requirements

### Analysis criteria:
- **Platform fit:** CrazyGames favors: idle/clicker, merge, .io-style, physics/ragdoll, driving/stunt, puzzle, tower defense, and action games. Simple controls, instant fun, short session loops.
- **Visual opportunity:** Since we're using Godot 4, the game concept should benefit from advanced visuals — particle systems, dynamic lighting, shaders, post-processing. This is our differentiator vs typical HTML5/Canvas games.
- **Technical feasibility for web:** Godot 4 web exports are heavier than pure HTML5. Must stay under 50MB initial load (ideally under 20MB for mobile). 2D with shaders is safer than 3D for file size. If 3D, keep it low-poly/stylized.
- **Retention hooks:** Must have progression (unlocks, upgrades, levels, scores). CrazyGames measures average playtime, conversion to gameplay, and retention.
- **Differentiation:** Must not be a direct clone. Needs a unique visual identity.

### Rendering decision:
- **2D with advanced shaders/particles** — safest for file size, still visually impressive
- **2.5D** (2D gameplay with 3D-looking visuals via shaders) — good balance
- **Low-poly 3D** — possible but watch file size carefully. Use Godot's built-in primitives, no heavy meshes.

### Deliverable:
Write a concise Game Design Document (GDD) covering:
- Game title and genre
- Core mechanic (1-2 sentences)
- Visual style and what Godot features make it shine (shaders, particles, lighting, etc.)
- Progression/retention loop
- Target session length
- 2D vs 3D decision with justification
- Estimated file size budget
- Why this will work on CrazyGames specifically

**Do not proceed until the GDD is written and confirmed.**

---

## STEP 2: Project Setup & Core Architecture

**Goal:** Set up the complete Godot 4 project structure, including CrazyGames SDK integration and web export configuration.

### Project structure:
```
project.godot
export_presets.cfg
/scenes/
    main.tscn            # Entry point / loading screen
    game.tscn            # Core gameplay scene
    menu.tscn            # Main menu
    hud.tscn             # In-game HUD
    game_over.tscn       # Game over / results screen
/scripts/
    main.gd
    game.gd
    menu.gd
    hud.gd
    game_over.gd
    crazy_sdk.gd         # CrazyGames SDK wrapper
    save_manager.gd      # Save/load via SDK data module
    audio_manager.gd     # Global audio with mute support
    game_manager.gd      # Global game state (autoload)
/shaders/
    (shader files)
/assets/
    /sprites/
    /audio/
    /fonts/
/addons/
    /crazysdk/           # CrazyGames Godot SDK plugin
```

### project.godot critical settings:
```ini
[rendering]
renderer/rendering_method="gl_compatibility"  ; REQUIRED for web — do NOT use Forward+ or Mobile

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[input]
; Define all input actions here — support both keyboard AND touch
```

**CRITICAL: Use `gl_compatibility` renderer.** Forward+ and Mobile renderers have limited/broken web support. gl_compatibility is the only reliable option for CrazyGames.

### Web export settings (export_presets.cfg):
```
[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"

[preset.0.options]
html/experimental_virtual_keyboard=true
html/export_icon=true
variant/extensions=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/canvas_resize_policy=2
; CRITICAL: Thread support OFF for CrazyGames
html/thread_support=false
```

**CRITICAL: `html/thread_support=false`** — CrazyGames does NOT support SharedArrayBuffer/Cross-Origin Isolation. Single-threaded export is mandatory.

### CrazyGames SDK Integration:

Download the official Godot SDK from: https://store-beta.godotengine.org/asset/crazygames/crazysdk

Create a wrapper singleton `crazy_sdk.gd` (autoload):

```gdscript
extends Node

var _sdk_available := false

func _ready() -> void:
    if OS.has_feature("web"):
        # Wait for SDK initialization
        await _init_sdk()

func _init_sdk() -> void:
    var initialized = JavaScriptBridge.eval("""
        (async () => {
            if (typeof CrazyGames !== 'undefined' && CrazyGames.SDK) {
                await CrazyGames.SDK.init();
                return true;
            }
            return false;
        })()
    """, true)
    # Use the CrazySDK autoload from the plugin instead if available
    # The plugin provides: CrazyGames.is_initialised, CrazyGames.is_initialised_async()
    _sdk_available = true

func is_available() -> bool:
    return _sdk_available and OS.has_feature("web")

# --- Gameplay events ---
func gameplay_start() -> void:
    if not is_available(): return
    # Using the CrazySDK plugin:
    CrazyGames.Game.gameplay_start()

func gameplay_stop() -> void:
    if not is_available(): return
    CrazyGames.Game.gameplay_stop()

func happy_time() -> void:
    if not is_available(): return
    CrazyGames.Game.happy_time()

# --- Ads ---
func show_midgame_ad(on_complete: Callable) -> void:
    if not is_available():
        on_complete.call()
        return
    
    var ad_started_cb = JavaScriptBridge.create_callback(_on_ad_started)
    var ad_finished_cb = JavaScriptBridge.create_callback(func(_args): 
        _on_ad_finished()
        on_complete.call()
    )
    var ad_error_cb = JavaScriptBridge.create_callback(func(_args):
        _on_ad_finished()
        on_complete.call()
    )
    CrazyGames.Ad.request_ad("midgame", ad_started_cb, ad_finished_cb, ad_error_cb)

func show_rewarded_ad(on_reward: Callable, on_skip: Callable) -> void:
    if not is_available():
        on_skip.call()
        return
    
    var ad_started_cb = JavaScriptBridge.create_callback(_on_ad_started)
    var ad_finished_cb = JavaScriptBridge.create_callback(func(_args):
        _on_ad_finished()
        on_reward.call()
    )
    var ad_error_cb = JavaScriptBridge.create_callback(func(_args):
        _on_ad_finished()
        on_skip.call()
    )
    CrazyGames.Ad.request_ad("rewarded", ad_started_cb, ad_finished_cb, ad_error_cb)

func _on_ad_started(_args = null) -> void:
    get_tree().paused = true
    AudioManager.mute_all()

func _on_ad_finished() -> void:
    get_tree().paused = false
    AudioManager.unmute_all()

# --- Data (save/load) ---
func save_data(key: String, value: String) -> void:
    if is_available():
        CrazyGames.Data.set_item(key, value)
    else:
        # Fallback to localStorage for local testing
        JavaScriptBridge.eval("localStorage.setItem('%s', '%s')" % [key, value])

func load_data(key: String) -> String:
    if is_available():
        return CrazyGames.Data.get_item(key)
    else:
        var result = JavaScriptBridge.eval("localStorage.getItem('%s')" % [key])
        return result if result else ""

# --- Settings listener ---
func _process(_delta: float) -> void:
    if not is_available(): return
    var settings = CrazyGames.Game.get_settings()
    if settings and settings.has("muteAudio") and settings.muteAudio:
        AudioManager.mute_all()
```

**Note:** The exact API depends on the CrazySDK plugin version. The plugin provides autoloads like `CrazyGames` with modules `Game`, `Ad`, `Data`, `User`. Adapt the above wrapper to match the plugin's actual API. Check the plugin's demo scene for reference.

### Ad rules (same as before, enforce in code):
- NEVER show an ad before the first gameplay session
- NEVER interrupt active gameplay
- Minimum 3 minutes between midgame ads
- Always pause game tree and mute audio during ads
- Rewarded ads must give a meaningful reward

### Audio Manager (autoload):
```gdscript
extends Node

var _muted := false
var _master_bus := AudioServer.get_bus_index("Master")

func mute_all() -> void:
    _muted = true
    AudioServer.set_bus_mute(_master_bus, true)

func unmute_all() -> void:
    _muted = false
    AudioServer.set_bus_mute(_master_bus, false)

func is_muted() -> bool:
    return _muted
```

### Input handling:
```gdscript
# In project.godot, define actions, NOT hardcoded keys
# Support WASD, arrows, AND touch

func _unhandled_input(event: InputEvent) -> void:
    # Prevent browser scroll on game keys
    if event is InputEventKey:
        get_viewport().set_input_as_handled()
```

### Deliverable:
- Complete project.godot
- export_presets.cfg
- All autoload scripts (crazy_sdk.gd, audio_manager.gd, game_manager.gd, save_manager.gd)
- Instructions for which Godot editor steps I need to do manually

---

## STEP 3: Build the Core Game

**Goal:** Create a fully playable game with core mechanics, basic progression, and all SDK hooks firing correctly.

### Technical requirements (non-negotiable):
- **Initial download ≤ 50MB** (target ≤ 20MB for mobile eligibility)
- **Total project ≤ 250MB**
- **16:9 viewport** (1920x1080 or 1280x720, with stretch mode)
- **gl_compatibility renderer** — no Forward+
- **Single-threaded web export** — no SharedArrayBuffer
- **Touch support** if targeting mobile
- **PEGI 12 compliant**
- **No external API calls** from game code

### Core game checklist:
- [ ] Game loads and runs in browser (test via Godot's built-in web server)
- [ ] Core mechanic is fun within 5 seconds
- [ ] Onboarding is visual (input prompts on screen), not text walls
- [ ] Max 1 click from load to gameplay
- [ ] Progression system works
- [ ] Save/load via CrazySDK Data module (with localStorage fallback)
- [ ] gameplay_start() / gameplay_stop() fire at correct moments
- [ ] Ad placements at natural break points (death, level complete)
- [ ] Input doesn't leak to browser (no scroll on arrow/space)
- [ ] Responsive to different viewport sizes

### Performance targets for web:
- Target 60fps on mid-range hardware
- Minimize draw calls — use texture atlases
- Avoid heavy physics — Godot's web physics is single-threaded and slow
- Use `Object.call_deferred()` for heavy operations
- Pre-load resources in loading screen
- Keep node count reasonable (< 500 active nodes)

### Deliverable:
All scene files (.tscn), scripts (.gd), and a step-by-step list of what I need to do in the Godot editor to assemble the game.

---

## STEP 4: Visual Polish — Make It Pop

**Goal:** This is why we're using Godot. Transform the game into something visually stunning that stands out from typical browser games. CrazyGames explicitly states: "Graphics should be of high quality."

### Godot-specific visual features to implement:

**Shaders (.gdshader):**
- Background shaders (animated gradients, noise-based patterns, parallax)
- Entity shaders (outline, glow, dissolve on death, flash on hit)
- Screen-wide post-processing (vignette, chromatic aberration on impact, bloom simulation)
- Water/liquid effects if relevant
- Example hit flash shader:
```gdshader
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = mix(tex, flash_color * tex.a, flash_amount);
}
```

**Particle systems (GPUParticles2D / CPUParticles2D):**
- Use **CPUParticles2D** for web (more reliable than GPU particles in gl_compatibility)
- Explosions, trails, sparkles, dust, confetti on achievements
- Death/destroy effects
- Ambient particles (floating dust, snow, embers)
- Collection effects (coins, items pickup)

**Tweening (create_tween()):**
- Nothing should snap — everything eases in/out
- Score counters animate up
- UI elements slide/fade in
- Screen shake on impacts:
```gdscript
func screen_shake(intensity: float = 10.0, duration: float = 0.2) -> void:
    var camera = get_viewport().get_camera_2d()
    if not camera: return
    var tween = create_tween()
    for i in range(int(duration / 0.02)):
        tween.tween_property(camera, "offset", 
            Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity, 0.02)
    tween.tween_property(camera, "offset", Vector2.ZERO, 0.05)
```

**Color & style:**
- Use a deliberate, limited palette
- Consistent art style throughout
- Background should not be flat — use parallax layers or animated shaders

**UI polish:**
- Buttons have hover/press states (StyleBoxFlat with varying colors)
- Theme resource for consistent fonts and colors
- Progress bars with smooth fill tweens
- Animated transitions between screens

**Audio:**
- Sound effects for all player actions
- Background music (looping, .ogg format for smaller size)
- Use AudioStreamPlayer / AudioStreamPlayer2D
- Respect SDK mute setting via AudioManager

**Happy time — use sparingly:**
```gdscript
# On genuine achievements only (high score, boss kill, milestone unlock)
CrazySdk.happy_time()
```

### Performance budget for visuals:
- Max ~50 active particle systems at once
- Shaders should be simple (avoid heavy loops in fragment())
- Use CanvasGroup for batch rendering where possible
- Profile with Godot's built-in profiler before export

### Deliverable:
Updated scene files and scripts with all visual effects. Shader files. List of any assets I need to create or source (with specifications).

---

## STEP 5: Retention & Engagement Optimization

**Goal:** Maximize CrazyGames metrics: average playtime, conversion to gameplay, and retention.

### Implement:
- **Meta-progression** — currency, unlocks, upgrades that persist between sessions
- **Daily/session rewards** — incentive to return
- **Difficulty curve** — easy start, gradual ramp, occasional spikes
- **"One more round" hooks** — show what's almost unlocked, next challenge preview
- **Rewarded ad value** — 2x coins, extra life, skip level. Must feel worth it.
- **Multiple game modes** if feasible (endless, challenge, timed)
- **Local leaderboard** display

### Anti-patterns to avoid:
- Hard gates or pay walls
- Ads that feel punishing
- Long waits with nothing to do
- Unexplained mechanics
- Dead ends with nothing left to achieve
- Overly aggressive ad frequency

---

## STEP 6: Submission Preparation

**Goal:** Package and optimize the Godot web export for CrazyGames submission.

### Web export optimization:
- **Compress textures:** Use ETC2/S3TC via export settings (vram_texture_compression for desktop + mobile)
- **Audio:** Convert all audio to .ogg (much smaller than .wav). Use mono for sound effects.
- **Fonts:** Only include needed characters/glyphs. Use .woff2 if possible, or Godot's bitmap fonts.
- **Remove unused assets** — Godot packs everything in the .pck
- **Strip debug symbols** — use Release export, not Debug
- **Measure initial load:** Everything before the first `gameplay_start()` counts as initial download

### Export steps (for me to follow):
1. Open Project > Export
2. Select "Web" preset
3. Ensure Thread Support = OFF
4. Ensure renderer = gl_compatibility (set in project settings)
5. Set export path
6. Click "Export Project" (not "Export PCK/ZIP")
7. Result: .html + .js + .wasm + .pck + other files
8. Zip the entire export folder
9. Test locally: `python -m http.server 8000` and open localhost:8000
10. Upload zip to CrazyGames Developer Portal

### Required submission assets:
- **Game cover image:** 512x512 PNG
- **Wide cover:** 1280x720 PNG
- **Gameplay video:** 15-30 second MP4 (capture from browser)
- **Game description:** 2-3 sentences
- **Controls description**
- **Tags/categories**

### Pre-submission checklist:
- [ ] Total zip < 250MB, initial load < 50MB (ideally < 20MB)
- [ ] File count < 1500
- [ ] 16:9 aspect ratio maintained
- [ ] Works in Chrome, Firefox, Edge (Safari may have issues with Godot web)
- [ ] Single-threaded export (no SharedArrayBuffer errors)
- [ ] gl_compatibility renderer (no WebGPU/Forward+ errors)
- [ ] Touch controls work (if mobile-enabled)
- [ ] CrazySDK initializes without errors
- [ ] gameplay_start/stop events fire correctly
- [ ] Ads show at natural break points (test via Preview tool)
- [ ] Data module saves/loads correctly
- [ ] No console errors in browser DevTools
- [ ] No external domain requests from game code
- [ ] PEGI 12 compliant content
- [ ] No fullscreen button (CrazyGames provides this)
- [ ] No app store links
- [ ] Unique game name
- [ ] Arrow keys / spacebar don't scroll the page
- [ ] Audio respects SDK mute setting
- [ ] Test via CrazyGames Preview tool in Developer Portal

### Deliverable:
Complete file manifest, export instructions, and submission metadata document.

---

## General rules for all steps:
- Write clean, well-commented GDScript
- Use typed variables (`var speed: float = 100.0`) for performance and clarity
- Use signals for loose coupling between nodes
- Test after every significant change
- Prioritize fun over feature count
- When in doubt, keep it simple — a polished simple game beats an unfinished complex one
- All SDK calls wrapped in `is_available()` checks for local development
- Always provide clear instructions for what I need to do manually in the editor
- **gl_compatibility renderer only** — never Forward+ or Mobile for web
- **Single-threaded export only** — never enable thread support for CrazyGames
