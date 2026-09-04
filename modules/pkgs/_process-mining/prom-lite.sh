#!@shell@
# shellcheck shell=bash
set -eu

export PATH=@coreutils@/bin:@util_linux@/bin:$PATH

# Swing paints nothing under a non-reparenting window manager -- niri,
# hyprland, i3 -- unless AWT is told the window manager is one.
export _JAVA_AWT_WM_NONREPARENTING=1

share='@share@'

# ProM keeps its downloaded packages, its workspace and its UI config next to
# ProM.ini, so run it from a writable directory. $PROM_HOME lets the dev shell
# put that somewhere that survives a reboot.
data="${PROM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/prom-lite}"
log="$data/prom-lite.log"
mkdir -p "$data"

# ProM logs every package it resolves and then sits there for the session, so
# by default give it its own session and a log file and hand the terminal back.
# --foreground keeps it attached, which is what you want when debugging.
if [ "${1:-}" = "--foreground" ]; then
  shift
else
  setsid "$0" --foreground "$@" >"$log" 2>&1 </dev/null &
  echo "prom-lite: started, logging to $log"
  exit 0
fi

ln -sfn "$share/dist" "$data/dist"
ln -sfn "$share/lib" "$data/lib"
[ -e "$data/ProM.ini" ] || install -m 644 "$share/ProM.ini" "$data/ProM.ini"
cd "$data"

classpath=
for jar in "$share"/dist/*.jar "$share"/lib/*.jar; do
  classpath="$classpath:$jar"
done

exec @java@ \
  -Xmx4G \
  -Duser.home="$data" \
  -da \
  -classpath "${classpath#:}" \
  -Djava.library.path="$share/lib" \
  -Djava.system.class.loader=org.processmining.framework.util.ProMClassLoader \
  -Djava.util.Arrays.useLegacyMergeSort=true \
  org.processmining.contexts.uitopia.UI "$@"
