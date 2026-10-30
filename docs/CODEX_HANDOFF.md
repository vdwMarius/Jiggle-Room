# Handoff: build and verify Jiggle Room into an Android APK

Paste everything below the line into Codex, or another agent with a Linux
shell and internet access.

---

You are taking over **Jiggle Room**, a Godot 4.3 (GDScript, Mobile renderer,
3D) jelly-physics toy for Android. Branch: `ccr-dd9ef0c5-55tbur`. All the code
was written **without ever being opened in Godot**, so expect a handful of
parse or API errors. Your job:

1. Make the project import and run with **zero script errors**.
2. Produce a **signed debug APK** at `build/JiggleRoom.apk` that installs and
   contains the `VIBRATE` permission.
3. Report exactly what you changed.

## Read first

* `README.md`: project layout and controls
* `docs/ARCHITECTURE.md`: how the jelly works. **Do not change the design.**
* `tools/ci/build_android.sh`: the build script you'll run

## Steps

1. Run `bash tools/ci/build_android.sh`. It installs JDK 17, Godot
   `4.3-stable` with export templates and the Android SDK (build-tools 34,
   platform 34). It then writes Godot editor settings, creates a debug
   keystore, imports the project, parse-checks every script, smoke-runs the
   game headless for about 10 s, exports the **"Android APK"** preset and
   verifies the result with `apksigner` and `aapt`.
   * After the first successful install, re-run with
     `SKIP_INSTALL=1 bash tools/ci/build_android.sh`.
   * Logs are in `build/logs/` (`import.log`, `check.log`, `run.log`,
     `export.log`).
2. **Fix errors in a loop until the script prints `SUCCESS`:**
   * Read the first error in the logs, fix the root cause, and re-run.
   * `check.log` can show false positives such as "Identifier GameState /
     Feedback / AdsService not declared", because `--check-only` doesn't load
     autoloads. `run.log` (the real game run) is authoritative.
   * Also fix every **warning that points at a real bug**, such as an unsafe
     cast to the wrong type or calling a method that doesn't exist. Ignore
     style warnings.
3. Things most likely to need attention (check them even if no error shows):
   * `shaders/jelly.gdshader` sends `ripple_origin` (a `vec4[8]`) as a
     *flattened* `PackedFloat32Array` (32 floats) from
     `scripts/jelly/jelly_springs.gd`. If Godot 4.3 rejects that, switch to
     `PackedVector4Array` or an `Array[Vector4]`.
   * Multi-line lambdas passed as function arguments (`scripts/ui/hud.gd`,
     `scripts/ui/ui_kit.gd`) must parse.
   * `Input.vibrate_handheld(ms, amplitude)` needs the 2-argument form
     (Godot 4.3+). If the installed version lacks it, drop the amplitude
     argument.
   * `export_presets.cfg` was hand-written. If the export complains about
     missing or invalid options, let Godot regenerate them. Keep
     `permissions/vibrate=true`, `architectures/arm64-v8a=true`,
     `gradle_build/use_gradle_build=false` and
     `package/unique_name="com.example.jiggleroom"`.
   * `.tres` files in `assets/jellies/` and `assets/rooms/` have no `uid=`
     entries. Godot adds them on import, so commit those changes.
   * Headless runs use the dummy renderer, so **shader compile errors may not
     appear**. If there's any way to compile shaders (e.g. `xvfb-run` with
     `--rendering-driver opengl3`, or the Compatibility renderer), run the
     game for 10 s that way too and fix any `SHADER ERROR`.
4. **(Optional, if time allows) a real runtime check.** With `xvfb-run` and a
   software GL available, run
   `xvfb-run -a <godot> --path . --rendering-driver opengl3 --quit-after 600`
   and confirm there are no errors. Take a screenshot if you can.

## Rules

* **Minimal fixes only.** Don't refactor, rename, reformat files or
  "simplify" the architecture: rigid body + springs + vertex shader, the
  single jelly shader with 8 ripple slots, procedural meshes, and the
  JellyData/RoomTheme resources all stay.
* **Don't change feel or tuning values** (stiffness, damping, frequencies,
  caps, default colours) unless they cause an actual crash.
* **Don't delete features** to make errors go away. Fix them. If something is
  truly impossible in Godot 4.3, stub it with a clear `push_warning` and list
  it in your report.
* **Don't add ad SDKs, analytics, network permissions or new dependencies.**
* **Never commit** the keystore, `build/`, `.godot/` or `android/`. They're
  already in `.gitignore`.
* Commit fixes in small, descriptive commits on branch `ccr-dd9ef0c5-55tbur`
  and push. Don't open a PR unless asked.

## Definition of done

* [ ] `tools/ci/build_android.sh` ends with `SUCCESS` from a clean checkout
* [ ] `build/logs/run.log` has no `SCRIPT ERROR` / `Parse Error` / `Invalid …`
      lines
* [ ] `build/JiggleRoom.apk` exists, `apksigner verify` passes, and
      `aapt dump permissions` lists `android.permission.VIBRATE`
* [ ] Fixes are committed and pushed
* [ ] The final report contains:
  1. The path to the APK and its size
  2. The Godot version used
  3. A list of every file changed, with a one-line reason each
  4. Any remaining warnings, or anything you couldn't verify (e.g. shaders
     under the dummy renderer)
  5. The exact command to rebuild

## Installing on a phone (for the human)

```bash
adb install -r build/JiggleRoom.apk
adb logcat -s godot     # watch for runtime errors while playing
```
