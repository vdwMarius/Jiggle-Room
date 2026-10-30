# Handoff: rebuild Jiggle Room v1.1.0 into an Android APK

Paste everything below the line into Codex, or another agent with a Linux
shell and internet access.

---

You are rebuilding **Jiggle Room**, a Godot 4 (GDScript, Mobile renderer, 3D)
jelly-physics toy for Android, on branch `ccr-dd9ef0c5-55tbur`.

**Background.** You built v1.0.0 from this branch with Godot **4.6.3**. Its
APK is in `releases/`. Since then commit `b60bac7` added a large feature
update, **written without ever being run in Godot**:

* a juicier jelly: new sway, sag and second-wobble springs, softer defaults,
  haptic wobble tail and a wobble sound;
* furnished real-scale rooms (living room, bedroom, playroom, kitchen,
  aquarium, space station), built by the new `scripts/room/furniture.gd`;
* a free orbit/pan/zoom camera inside the room (`scripts/util/camera_rig.gd`,
  driven from `scripts/input/touch_controller.gd`).

Expect a few parse, API or runtime errors. Your job:

1. Make the project import and run with **zero script errors**, and make the
   new functional smoke test pass.
2. Produce a **signed debug APK, version 1.1.0 (code 2)**, at
   `build/JiggleRoom.apk`, and publish it to `releases/`, replacing v1.0.0.
3. Report exactly what you changed.

## Read first

* `README.md`: controls and project layout
* `docs/ARCHITECTURE.md`: how the jelly, rooms and camera work. **Do not change the design.**
* `releases/README.md`: how you published v1.0.0. Follow the same format.
* `tools/ci/build_android.sh` and `tools/ci/smoke_test.gd`

## Steps

1. **Use the same toolchain as v1.0.0.** The script now defaults to
   `GODOT_VERSION=4.6.3`, `BUILD_TOOLS=35.0.1` and `PLATFORM=android-35`, and
   all three can be overridden with env vars. If your previous install is
   still there:
   `SKIP_INSTALL=1 bash tools/ci/build_android.sh`.
   Otherwise run it without `SKIP_INSTALL`.
2. **Reuse the v1.0.0 signing key if you still have it** (by default
   `~/.jiggle-tools/debug.keystore`, or wherever you kept it). A different key
   forces the user to uninstall v1.0.0 first, which wipes their save data.
   If the key is gone, say so clearly in the report and in
   `releases/README.md`.
3. The script imports the project, parse-checks every script, runs the game
   headless for 600 frames, and then runs **`tools/ci/smoke_test.tscn`**. That
   test:
   * builds every room and checks it has furniture and its own size;
   * spawns every jelly and lets them land;
   * pokes, jolts, grabs, resizes and shakes them, checking the springs stay
     finite and within their caps;
   * orbits, pans, zooms, focuses and resets the camera, checking it stays
     inside the room;
   * cycles gravity, slow-mo, wall modes and props;
   * merges two jellies, and enters and exits photo mode.

   It must print `SMOKE OK` with no error lines in `build/logs/smoke.log`.
   The script then exports and verifies the APK.
4. **Fix errors in a loop until the script prints `SUCCESS`.** Read the first
   error in `build/logs/` (`import.log`, `check.log`, `run.log`, `smoke.log`,
   `export.log`), fix its root cause, and re-run.
   * `check.log` can report false "identifier not declared" errors for the
     autoloads (`GameState`, `Feedback`, `AdsService`) and for class names.
     The run and smoke logs are authoritative.
   * If a `SMOKE FAIL` is a wrong *test expectation* rather than a game bug,
     fix the test and explain why in your report. Never weaken a check just
     to get green.
5. **Most likely trouble spots in the new code.** Check these even if nothing
   errors:
   * `scripts/room/furniture.gd`: static vars and the static material cache,
     `squash := Vector3.ONE` default params, and pieces built inside rotated
     pivot nodes (the slide ramp). Every `Furniture.*` builder is called from
     `Room._rebuild_furniture` via `match theme.layout:`.
   * `scripts/util/camera_rig.gd`: Vector3 indexing in `_distance_to_walls`,
     `lerp_angle` smoothing, and `process_mode = ALWAYS` so it works while
     paused.
   * `scripts/input/touch_controller.gd`: new camera paths (`_cam_pinch`,
     `orbiting`, double-tap) and the `_drag_plane` helper.
   * `shaders/jelly.gdshader`: the new uniforms (`ground_up`,
     `ground_anchor`, `body_height`, `sag`, `sway`, `wobble2`,
     `wobble2_axis`) and the sway shear (`pow(h, 1.5)`, `sqrt(h)`). Headless
     uses the dummy renderer, so shader errors **won't show**. If you can,
     run with a real GL driver (e.g.
     `xvfb-run -a <godot> --path . --rendering-driver opengl3 --quit-after 600`,
     or the same command with `res://tools/ci/smoke_test.tscn`) and fix every
     `SHADER ERROR`.
   * `shaders/room_surface.gdshader`: new patterns 8 (tiles) and 9 (carpet).
   * `scripts/autoload/feedback.gd`: `_wobble_tail` is a coroutine using
     `create_timer(..., false, false, false)`.
   * `scripts/autoload/game_state.gd`: save version 2 migration (renames
     `cosy_lounge` to `living_room` and drops old feel overrides).
   * `assets/rooms/*.tres` and `assets/jellies/*.tres` were hand-written.
     Commit any `uid=` lines Godot adds.
6. **Publish** (same as v1.0.0):
   * Copy `build/JiggleRoom.apk` to `releases/JiggleRoom-debug.apk`.
   * Regenerate `releases/JiggleRoom-debug.apk.sha256`.
   * Update `releases/README.md`: version **1.1.0 (2)**, Godot version,
     whether the signing key is the same as 1.0.0, a short "What's new"
     (juicier wobble, furnished rooms, free camera), and the verification
     you actually did (smoke test results, any GL/shader run).
   * Keep `releases/.gdignore`.

## Rules

* **Minimal fixes only.** Don't refactor, rename, reformat or "simplify".
  Keep rigid body + springs + vertex shader, the single jelly shader,
  procedural meshes, the `Furniture` builders, the orbit camera, and the
  JellyData/RoomTheme resources.
* **Don't change feel or tuning values** (frequencies, damping, stiffness,
  caps, sway, sag, secondary wobble), furniture layout or camera constants,
  unless they cause a crash or a failing smoke check. If you do change one,
  justify it.
* **Don't delete features** to make errors go away. If something is truly
  impossible in this Godot version, stub it with a clear `push_warning` and
  list it in the report.
* **Don't add dependencies, ad SDKs, analytics or permissions.** The APK must
  keep `VIBRATE` and must **not** have `INTERNET`.
* **Never commit** a keystore, `build/`, `.godot/`, `android/` or
  credentials.
* Commit fixes in small, descriptive commits on `ccr-dd9ef0c5-55tbur`,
  separate from the release commit, and push. Don't open a PR unless asked.

## Definition of done

- [ ] `tools/ci/build_android.sh` ends with `SUCCESS`
- [ ] `build/logs/smoke.log` contains `SMOKE OK` and no `SMOKE FAIL`, `SCRIPT ERROR`, `Parse Error` or `Invalid …` lines
- [ ] `aapt dump badging` shows `versionCode='2'` and `versionName='1.1.0'`
- [ ] `apksigner verify` passes; `VIBRATE` is present and `INTERNET` is absent
- [ ] `releases/` is updated (APK, sha256, README) and everything is pushed
- [ ] The final report lists:
  1. APK path, size and SHA-256
  2. Godot and build-tools versions
  3. Whether the signing key matches v1.0.0 (i.e. whether it upgrades in place)
  4. Every file changed, with a one-line reason each
  5. Smoke test output (the `SMOKE …` lines)
  6. What couldn't be verified (shaders without GL, touch input, real-device feel)
  7. The exact rebuild command

## Installing on the phone (for the human)

```bash
adb install -r releases/JiggleRoom-debug.apk   # in-place upgrade if the key matches
adb logcat -s godot                            # watch for runtime errors while playing
```

If the install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, the signing
key changed. Uninstall the old version first (this wipes the save).
