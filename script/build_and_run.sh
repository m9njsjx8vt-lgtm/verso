#!/usr/bin/env bash
# Build and launch Verso from a deterministic project-local build directory.

set -euo pipefail

MODE="${1:-run}"
APP_NAME="Verso"
BUNDLE_ID="com.tomoro.verso"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Verso.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen >/dev/null
elif [ ! -d "$PROJECT_PATH" ]; then
  echo "xcodegen is required because $PROJECT_PATH is missing." >&2
  echo "Install it with: brew install xcodegen" >&2
  exit 1
fi

SIGNING_ARGS=()
if ! security find-identity -v -p codesigning | grep -F '"Verso Self-Signed"' >/dev/null 2>&1; then
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}" \
  build

if [ ! -d "$APP_BUNDLE" ]; then
  echo "$APP_BUNDLE was not produced." >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running from $APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
