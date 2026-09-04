#!@shell@
# shellcheck shell=bash
set -eu

export PATH=@coreutils@/bin:@util_linux@/bin:$PATH

share='@share@'
data="${CPN_IDE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/cpn-ide}"
log="$data/cpn-ide.log"
tmp="$data/tmp"
simulator="$tmp/accesscpn/simulator"
mkdir -p "$data"

# The window is the session, and it outlives the shell that started it, so by
# default detach and log to a file. --foreground keeps it attached.
if [ "${1:-}" = "--foreground" ]; then
  shift
else
  setsid "$0" --foreground "$@" >"$log" 2>&1 </dev/null &
  echo "cpn-ide: starting, logging to $log"
  exit 0
fi

# The Access/CPN engine only unpacks its simulator if it is not there yet, so
# seeding this directory with the patched binaries makes it use those.
mkdir -p "$simulator"
for binary in "$share"/simulator/*; do
  target="$simulator/$(basename "$binary")"
  [ -e "$target" ] || install -m 755 "$binary" "$target"
done

# The frontend defaults to talking to port 8080; if you move it, set the server
# address in the IDE's settings to match.
port="${CPN_IDE_PORT:-8080}"
url="http://localhost:$port/"

@java@ \
  -server \
  -DPROP_FILE="$share/application.properties" \
  -Dserver.port="$port" \
  -Duser.home="$data" \
  -Dspring.resources.static-locations="file:$share/web/" \
  -Djava.io.tmpdir="$tmp" \
  -jar "$share/cpn-ide-back.jar" >"$data/backend.log" 2>&1 &
backend=$!
trap 'kill $backend 2>/dev/null || true' EXIT INT TERM

for _ in $(seq 120); do
  @curl@ -sfo /dev/null "$url" && break
  kill -0 $backend 2>/dev/null || {
    echo "cpn-ide: the backend stopped before it came up; see $data/backend.log" >&2
    exit 1
  }
  sleep 0.5
done

if [ -n "${CPN_IDE_BROWSER:-}" ]; then
  echo "CPN IDE is running on $url"
  @xdg_open@ "$url" >/dev/null 2>&1 || true
  wait $backend
else
  # The window owns the session: closing it returns here, and the trap stops
  # the backend. Not exec, or there would be no shell left to run the trap.
  CPN_IDE_URL="$url" @electron@ "$share/app" "$@"
fi
