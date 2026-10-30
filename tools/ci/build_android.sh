#!/usr/bin/env bash
# Jiggle Room - headless Linux build: installs toolchain, imports, checks
# scripts, exports a signed debug APK and verifies it.
#
#   tools/ci/build_android.sh            # full run
#   SKIP_INSTALL=1 tools/ci/build_android.sh   # reuse installed toolchain
#
# Output: build/JiggleRoom.apk and build/logs/*.log
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.3}"
GODOT_FLAVOR="${GODOT_FLAVOR:-stable}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.jiggle-tools}"
ANDROID_HOME="${ANDROID_HOME:-$TOOLS_DIR/android-sdk}"
BUILD_TOOLS="34.0.0"
PLATFORM="android-34"
PRESET="Android APK"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/build"
LOGS="$BUILD/logs"
mkdir -p "$TOOLS_DIR" "$BUILD" "$LOGS"

GODOT_TAG="${GODOT_VERSION}-${GODOT_FLAVOR}"
GODOT_BIN="$TOOLS_DIR/Godot_v${GODOT_TAG}_linux.x86_64"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_FLAVOR}"
KEYSTORE="$TOOLS_DIR/debug.keystore"

log() { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- toolchain
install_toolchain() {
  log "Java 17"
  if ! java -version 2>&1 | grep -q '"17'; then
    if command -v apt-get >/dev/null; then
      sudo apt-get update -y && sudo apt-get install -y openjdk-17-jdk-headless unzip curl
    else
      die "Install OpenJDK 17 and put it on PATH"
    fi
  fi
  export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"

  log "Godot ${GODOT_TAG}"
  if [[ ! -x "$GODOT_BIN" ]]; then
    curl -fsSL -o "$TOOLS_DIR/godot.zip" \
      "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip"
    unzip -o -q "$TOOLS_DIR/godot.zip" -d "$TOOLS_DIR"
    chmod +x "$GODOT_BIN"
  fi

  log "Export templates"
  if [[ ! -f "$TEMPLATE_DIR/android_debug.apk" ]]; then
    curl -fsSL -o "$TOOLS_DIR/templates.tpz" \
      "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_export_templates.tpz"
    rm -rf "$TOOLS_DIR/templates"
    unzip -o -q "$TOOLS_DIR/templates.tpz" -d "$TOOLS_DIR"
    mkdir -p "$TEMPLATE_DIR"
    cp -r "$TOOLS_DIR/templates/." "$TEMPLATE_DIR/"
  fi

  log "Android SDK (build-tools ${BUILD_TOOLS}, ${PLATFORM})"
  if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    curl -fsSL -o "$TOOLS_DIR/cmdline.zip" \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    unzip -o -q "$TOOLS_DIR/cmdline.zip" -d "$ANDROID_HOME/cmdline-tools"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  fi
  yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
  "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
    "platform-tools" "build-tools;${BUILD_TOOLS}" "platforms;${PLATFORM}" >/dev/null
}

if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
  install_toolchain
fi
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
[[ -x "$GODOT_BIN" ]] || die "Godot binary missing at $GODOT_BIN"

# ---------------------------------------------------------------- keystore + editor settings
log "Debug keystore"
if [[ ! -f "$KEYSTORE" ]]; then
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
    -keystore "$KEYSTORE" -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -noprompt
fi
# Godot 4.2+ also reads these env vars during export.
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

log "Editor settings (SDK/JDK/keystore paths)"
CONF="$HOME/.config/godot"
mkdir -p "$CONF"
SETTINGS=$(cat <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
)
# File name differs between Godot minor versions; write the common ones.
for f in "editor_settings-4.tres" "editor_settings-${GODOT_VERSION}.tres"; do
  printf '%s\n' "$SETTINGS" > "$CONF/$f"
done

GODOT=("$GODOT_BIN" --headless --path "$ROOT")

# ---------------------------------------------------------------- import
log "Import project (builds .godot/ cache, registers class_names)"
"${GODOT[@]}" --import >"$LOGS/import.log" 2>&1 \
  || "${GODOT[@]}" --editor --quit >>"$LOGS/import.log" 2>&1 || true
# Second pass: class_name cache is complete only after the first import.
"${GODOT[@]}" --editor --quit >>"$LOGS/import.log" 2>&1 || true

# ---------------------------------------------------------------- script check
ERR_PATTERN='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Invalid call|Invalid get|Invalid set|Invalid access|Cannot infer|Nonexistent function|ERROR: .*\.gd'
log "Parse check: every .gd file"
: >"$LOGS/check.log"
while IFS= read -r f; do
  rel="res://${f#"$ROOT"/}"
  "${GODOT[@]}" --check-only --script "$rel" >>"$LOGS/check.log" 2>&1 || echo "CHECK FAILED: $rel" >>"$LOGS/check.log"
done < <(find "$ROOT/scripts" -name '*.gd' | sort)
# --check-only on autoload-dependent scripts can report false "identifier not
# declared" errors for GameState/Feedback/AdsService; the smoke run below is
# authoritative for those.

log "Smoke run: start the game headless for ~10 s"
"${GODOT[@]}" --quit-after 600 >"$LOGS/run.log" 2>&1 || true

if grep -Eq "$ERR_PATTERN" "$LOGS/import.log" "$LOGS/run.log"; then
  grep -En "$ERR_PATTERN" "$LOGS/import.log" "$LOGS/run.log" | head -60
  die "Script/runtime errors found (see build/logs/). Fix them and re-run."
fi
if grep -Eq 'CHECK FAILED|Parse Error' "$LOGS/check.log"; then
  echo "--check-only reported issues (verify they are not autoload false positives):"
  grep -En 'CHECK FAILED|Parse Error|SCRIPT ERROR' "$LOGS/check.log" | head -40
fi

# ---------------------------------------------------------------- export
log "Export '${PRESET}' (debug, signed)"
rm -f "$BUILD/JiggleRoom.apk"
"${GODOT[@]}" --export-debug "$PRESET" "$BUILD/JiggleRoom.apk" >"$LOGS/export.log" 2>&1 || true
if [[ ! -s "$BUILD/JiggleRoom.apk" ]]; then
  tail -60 "$LOGS/export.log"
  die "APK was not produced (see build/logs/export.log)"
fi

# ---------------------------------------------------------------- verify
log "Verify APK"
BT="$ANDROID_HOME/build-tools/$BUILD_TOOLS"
"$BT/apksigner" verify --print-certs "$BUILD/JiggleRoom.apk" | head -5
"$BT/aapt" dump badging "$BUILD/JiggleRoom.apk" | grep -E "^package:|sdkVersion|native-code" || true
"$BT/aapt" dump permissions "$BUILD/JiggleRoom.apk" | grep -q "android.permission.VIBRATE" \
  || die "VIBRATE permission missing from APK"
unzip -l "$BUILD/JiggleRoom.apk" | grep -q "assets/" || die "APK has no packed assets"

ls -lh "$BUILD/JiggleRoom.apk"
log "SUCCESS: $BUILD/JiggleRoom.apk"
