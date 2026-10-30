# Jiggle Room Android download

Download [JiggleRoom-debug.apk](JiggleRoom-debug.apk) using GitHub's **Download raw file** button, then open it on your phone. Allow your browser or file manager to install unknown apps when Android prompts you.

- Version: 1.1.0 (2)
- Package: `com.example.jiggleroom`
- Device: 64-bit ARM Android 7.0+ (API 24), with Vulkan support for the Mobile renderer.
- Build: Godot 4.6.3 standard, signed debug APK for sideload testing.
- Permission: `android.permission.VIBRATE`; no Internet permission.

The APK is debug-signed, not a Google Play release. It uses the **same signing key as v1.0.0**, so `adb install -r releases/JiggleRoom-debug.apk` supports an in-place upgrade without deleting save data. The key is not committed. Its signing certificate SHA-256 is `1a9d8eb3d9dcf5294524b5f300453be551b42abbaf2148666890b3a8379ae713`.

## What's new

- Juicier wobble with sway, sag, secondary springs, and wobble sound/haptic feedback.
- Six furnished rooms with their own sizes and primitive-built furniture.
- Free orbit, pan, and zoom camera, including photo-mode controls.

## Verification

`JiggleRoom-debug.apk.sha256` records the download checksum. Verify it from this directory with:

```sh
sha256sum -c JiggleRoom-debug.apk.sha256
```

`tools/ci/build_android.sh` completed with `SUCCESS`. Its 600-frame headless game run and functional smoke scene completed without script/runtime errors. The smoke test exercised all six rooms, all seven jellies, poke/jolt/grab/resize/shake, camera movement, gravity/slow motion/wall modes/props, merging, and photo mode, ending with `SMOKE OK`.

Android SDK Build-Tools 35.0.1 verified v2/v3 signatures and 16 KB native-library ZIP alignment. Manifest inspection confirmed version 1.1.0 (code 2), the launcher, ARM64 architecture, VIBRATE permission, and no INTERNET permission. The signing certificate was compared directly with the previous v1.0.0 APK and matches.

The legacy `aapt dump badging` prints the correct version but reports an unsupported attribute representation in the Godot template; `aapt2` successfully inspected the complete manifest and permissions. Standalone `--check-only` reports the documented missing-autoload false positives; the imported game and full smoke scene run successfully.

The complete smoke scene also passed (`SMOKE OK`) under software OpenGL 4.5 Compatibility using Mesa llvmpipe, with no shader or runtime errors. The existing Xorg dummy display was used; no game dependencies were added. The successful command (with the XDG variables below set) was:

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 360x640 --verbose res://tools/ci/smoke_test.tscn
```

Remaining warnings: the virtual graphics driver cannot set VSync, and two pending `SceneTreeTimer` instances remain at smoke-test shutdown. The first graphical attempt also reported a missing ALSA device; selecting dummy audio resolved that environment error for the successful run. Physical-device installation/upgrade, Vulkan/Mobile shader execution, touch input, audible sound, haptics, and real-device feel/performance remain unverified.

## Rebuild

Reuse the original debug keystore, Godot 4.6.3, its matching Android debug export template, Android SDK platform 35 and Build-Tools 35.0.1. This environment also retains the same OpenJDK 21 used for v1.0.0. In the prepared cloud environment, from `/workspace/Jiggle-Room`, the exact build command is:

```sh
export XDG_CACHE_HOME=/workspace/.jiggle-runtime/cache
export XDG_DATA_HOME=/workspace/.jiggle-runtime/data
export XDG_CONFIG_HOME=/workspace/.jiggle-runtime/config
SKIP_INSTALL=1 TOOLS_DIR=/workspace/.jiggle-tools bash tools/ci/build_android.sh
```

On another machine, configure `TOOLS_DIR`, `ANDROID_HOME`, and the Godot template directory for that machine, and preserve the original keystore for upgrade compatibility. See `docs/ANDROID_EXPORT.md`.

`releases/.gdignore` keeps these distribution files out of Godot's resource import and subsequent exports.
