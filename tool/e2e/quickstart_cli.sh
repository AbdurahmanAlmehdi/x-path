#!/usr/bin/env bash
# The CLI-only path of docs/guide/quickstart.md, end to end (U8), so that the
# page cannot drift from what works:
#
#   quickstart_cli.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`), then does what the
# page says, in a temporary folder:
#
#   - `xpd token create` makes a `cli` token, and `xpd serve` starts the engine
#     (XPD_TEST_FILE_SECRETS: its secrets in a file, never in the Keychain),
#   - `xp connect` connects the CLI (XP_TEST_FILE_SECRETS and XP_CONFIG_DIR:
#     its settings and token in the temporary folder),
#   - `xp status` and `xp doctor` answer,
#   - `xp projects add` adds a copy of the fixture app (tool/e2e/build_app,
#     with one test) whose origin is a file:// repository, so no GitHub,
#   - `xp dispatch <app> test --follow` runs the built-in `test` workflow and
#     exits 0 only when the run succeeded.
#
# It needs Dart and the Flutter version the fixture pins (3.47.6) first on
# PATH, and git; the engine links the Flutter SDK of this machine into its
# toolchain cache. Set XPATH_E2E_FLUTTER_SDK to an SDK folder that already is
# the pinned version to skip the search for it. Works on macOS and on Linux,
# and in the runner image.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
engine_pid=""
cleanup() {
  [[ -n "$engine_pid" ]] && kill "$engine_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "quickstart_cli: $*" >&2
  [[ -f "$work/xpd.log" ]] && { echo "--- xpd log ---" >&2; tail -n 40 "$work/xpd.log" >&2; }
  exit 1
}

for tool in dart flutter git; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"
done

flutter_sdk="${XPATH_E2E_FLUTTER_SDK:-}"
if [[ -z "$flutter_sdk" ]]; then
  flutter_bin="$(command -v flutter)"
  flutter_sdk="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
fi

build() {
  local app="$1" name="$2"
  echo "Building the $name bundle..."
  (cd "$root/apps/$app" && dart build cli -t "bin/$name.dart" -o "$work/build-$name" >"$work/build-$name.log" 2>&1) \
    || { cat "$work/build-$name.log" >&2; fail "dart build cli failed for $name"; }
  [[ -x "$work/build-$name/bundle/bin/$name" ]] || fail "no executable at $work/build-$name/bundle/bin/$name"
}
build xpd xpd
build xp xp
xpd="$work/build-xpd/bundle/bin/xpd"
xp="$work/build-xp/bundle/bin/xp"

# The app: a clone of a file:// repository, as a project on any git host is.
echo "Making the app repository..."
origin="$work/quickstart_app.git"
app="$work/quickstart_app"
cp -R "$root/tool/e2e/build_app" "$app"
mkdir -p "$app/test"
cat >"$app/test/quickstart_test.dart" <<'DART'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds', () => expect(1 + 1, 2));
}
DART
cat >>"$app/pubspec.yaml" <<'YAML'

dev_dependencies:
  flutter_test:
    sdk: flutter
YAML
git init -q --bare "$origin"
(
  cd "$app"
  git init -q -b main
  git add -A
  git -c user.name=quickstart -c user.email=quickstart@example.com commit -q -m "chore: quickstart app"
  git remote add origin "file://$origin"
  git push -q origin main
) || fail "could not make the app repository"

# The engine.
data="$work/data"
pin="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$app/.fvmrc")"
mkdir -p "$data/toolchains/flutter"
ln -s "$flutter_sdk" "$data/toolchains/flutter/$pin"
export XPD_TEST_FILE_SECRETS=1
token="$("$xpd" token create --data-dir "$data" --name quickstart --kind cli)"
[[ "$token" == xpt_* ]] || fail "xpd token create printed no token"

echo "Starting the engine..."
"$xpd" serve --port 0 --data-dir "$data" >"$work/xpd.log" 2>&1 &
engine_pid=$!
url=""
for _ in $(seq 1 120); do
  url="$(grep -o 'http://[^ ]*' "$work/xpd.log" | head -n 1 || true)"
  [[ -n "$url" ]] && break
  kill -0 "$engine_pid" 2>/dev/null || fail "xpd exited before it listened"
  sleep 0.5
done
[[ -n "$url" ]] || fail "xpd did not listen within 60 s"

# The CLI, as the page runs it.
export XP_TEST_FILE_SECRETS=1 XP_CONFIG_DIR="$work/xp-config" XP_NO_UPDATE_CHECK=1
"$xp" connect "$url" --token "$token" || fail "xp connect failed"
"$xp" status || fail "xp status failed"
"$xp" doctor || fail "xp doctor failed"
"$xp" projects add "$app" || fail "xp projects add failed"
echo "Running the test workflow..."
"$xp" dispatch quickstart_app test --follow || fail "the test run did not succeed"

echo "OK: the CLI quickstart connected to a new engine, added a project from a file:// repository and ran the built-in test workflow green."
