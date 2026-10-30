# Android export

## One-time setup

1. **Godot export templates:** *Editor → Manage Export Templates → Download
   and Install* (must match your editor version).
2. **Android SDK:** install Android Studio, or just the command-line tools.
   Through the SDK Manager, install:
   * Android SDK Platform-Tools
   * Android SDK Build-Tools **34.x**
   * Android SDK Platform **34** (Godot 4.3 targets API 34)
   * CMake and NDK (side by side): only needed for Gradle builds or plugins
3. **OpenJDK 17.**
4. In *Editor → Editor Settings → Export → Android*, set:
   * `Java SDK Path` (JDK 17)
   * `Android SDK Path`
   * `Debug Keystore`: Godot generates one automatically in 4.3. Otherwise:
     `keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999`

## Presets included (`export_presets.cfg`)

| Preset | Output | Use |
| --- | --- | --- |
| **Android APK** | `build/JiggleRoom.apk`, arm64-v8a, no Gradle | Sideload / quick testing / one-click deploy |
| **Android AAB (Play Store)** | `build/JiggleRoom.aab`, armv7 + arm64, Gradle build | Google Play upload (Play requires AAB) |

Before release, change `package/unique_name` from `com.example.jiggleroom` to
your own reverse-domain id.

### Permissions

| Permission | Why | Preset setting |
| --- | --- | --- |
| `VIBRATE` | Haptics (`Input.vibrate_handheld`) | `permissions/vibrate=true` ✔ |
| `INTERNET` | Only for rewarded ads (AAB preset). Turn it off if you ship without ads | `permissions/internet` |
| *(none)* | Accelerometer and gravity sensors need no permission | — |
| *(none)* | Screenshots and GIFs are saved in app storage (`user://photos/`) | — |

> **Saving to the Gallery:** on Android 10+ (scoped storage) an app can't
> write straight into `/sdcard/Pictures` without the MediaStore API.
> `PhotoMode._export_copy` tries and quietly falls back to app storage. To put
> photos in the user's gallery or share sheet, add an Android plugin that
> wraps `MediaStore` or `Intent.ACTION_SEND` (several Godot 4 "share" plugins
> exist) and call it from `_export_copy`. Don't request
> `MANAGE_EXTERNAL_STORAGE`: Play rejects it for this use.

### Orientation

`display/window/handheld/orientation = 6` (*sensor*) allows portrait and
landscape. The HUD and room re-layout on `size_changed`. The tilt-gravity
mode uses `Input.get_gravity()`, which Godot already corrects for screen
rotation.

### Display

* `screen/immersive_mode=true` hides the system bars. The HUD respects the
  notch and gesture-bar safe area (`DisplayServer.get_display_safe_area`).
* Stretch mode `canvas_items` + `expand` with a 720×1280 base keeps buttons
  large on every DPI.

## Build an APK (debug / sideload)

1. *Project → Export → Android APK → Export Project*. Untick *Export With
   Debug* for release, which needs a release keystore (below).
2. Or connect a phone with USB debugging on and press the **Android
   one-click deploy** button (top right of the editor).

## Build an AAB for Google Play

1. *Project → Install Android Build Template* (creates `android/`, which is
   git-ignored).
2. Create a release keystore:
   `keytool -v -genkey -keystore jiggleroom-release.keystore -alias jiggleroom -keyalg RSA -validity 10000`
3. In the **Android AAB** preset, under *Keystore → Release*, set the path,
   user and password. Godot keeps these in `.godot/export_credentials.cfg`,
   which is not committed.
4. Bump `version/code` for every upload.
5. *Export Project* → `JiggleRoom.aab` → upload to the Play Console. Enrol in
   Play App Signing.

## Rewarded ads (optional)

1. Install a Godot 4 AdMob Android plugin (for example *Poing Studios
   godot-admob-plugin*). Follow its instructions, which typically require the
   Gradle build and an `APPLICATION_ID` in the manifest.
2. Fill in `AdsService._show_plugin_ad()` in
   `scripts/autoload/ads_service.gd`. Show the rewarded ad, and emit
   `reward_granted(reward_id)` from the plugin's "user earned reward"
   callback.
3. Keep it player-initiated only. The UI shows "Watch ad to unlock" next to
   locked items, and there are no interstitials or banners.
4. Fill in the Play Console Data safety form and add a privacy policy, since
   ad SDKs collect device identifiers.

## Performance checklist (60 FPS on mid-range)

* Renderer: **Mobile** (Vulkan). On very old GPUs, switch to *Compatibility*.
  The jelly shader works there too (screen texture is supported).
* MSAA 2× is on (`msaa_3d=1`). Turn it off if you're fill-rate bound.
* Keep jelly meshes under 5k vertices and at most 8 jellies (`MAX_JELLIES`).
* There's one shadowed directional light. Disable `shadow_enabled` in
  `room.gd` for low-end devices.
* Physics runs at 60 Hz with convex hulls. Use `collision = SPHERE` on
  low-end devices.
* Profile on the device with *Debug → Deploy with Remote Debug* and the
  Profiler/Monitors tabs. Watch *Process time*, *Physics time* and *Draw
  calls*.
