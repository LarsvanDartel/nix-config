#!@shell@
# shellcheck shell=bash
set -eu

export PATH=@coreutils@/bin:@util_linux@/bin:$PATH

# Swing paints nothing under a non-reparenting window manager -- niri,
# hyprland, i3 -- unless AWT is told the window manager is one.
export _JAVA_AWT_WM_NONREPARENTING=1

share='@share@'

# ProM keeps its packages/workspace/config next to ProM.ini, so it must run
# from a writable directory.
data="${PROM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/prom-lite}"
log="$data/prom-lite.log"
mkdir -p "$data"

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
