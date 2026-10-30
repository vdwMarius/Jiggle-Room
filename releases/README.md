# Jiggle Room Android download

Download [JiggleRoom-debug.apk](JiggleRoom-debug.apk) using GitHub's **Download raw file** button, then open it on your phone. Allow your browser or file manager to install unknown apps when Android prompts you.

- Version: 1.0.0 (1)
- Package: `com.example.jiggleroom`
- Device: 64-bit ARM Android 7.0+ (API 24), with Vulkan support for the Mobile renderer.
- Build: Godot 4.6.3 standard, signed debug APK for sideload testing.
- Permission: `android.permission.VIBRATE`; no Internet permission.

The APK is debug-signed, not a Google Play release. Its signing key is not committed. Future builds signed with a different key require uninstalling this build first, which removes its local save data.

## Verification

`JiggleRoom-debug.apk.sha256` records the download checksum. Verify it from this directory with:

```sh
sha256sum -c JiggleRoom-debug.apk.sha256
```

Before distribution, Android SDK Build-Tools 35.0.1 verified the v2/v3 APK signatures and 16 KB native-library ZIP alignment. The manifest contains the launcher activity, ARM64 architecture, and vibration permission. The game passed a 600-frame headless run and functional checks of scene creation, room, HUD, jelly spawning, slow motion, gravity, and physics. Physical-device installation, touch input, and graphical shader rendering have not been tested.

## Rebuild

Install Godot 4.6.3 and its matching Android export templates. Configure the Android SDK, JDK, and debug keystore in Godot's editor settings (see `docs/ANDROID_EXPORT.md`). From the repository root:

```sh
mkdir -p build
godot --headless --path . --editor --import --quit
godot --headless --path . --export-debug 'Android APK' build/JiggleRoom.apk
```

`releases/.gdignore` keeps these distribution files out of Godot's resource import and subsequent exports.
