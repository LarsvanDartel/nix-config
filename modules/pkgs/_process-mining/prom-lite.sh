#!@shell@
# shellcheck shell=bash
set -eu

export PATH=@coreutils@/bin:@util_linux@/bin:$PATH

# Swing paints nothing under a non-reparenting window manager -- niri,
# hyprland, i3 -- unless AWT is told the window manager is one.
export _JAVA_AWT_WM_NONREPARENTING=1

# The Inductive visual Miner's animation unpacks JOGL natives that link the X11
# libraries and dlopen libGL by soname; NixOS has neither on the search path.
export LD_LIBRARY_PATH=@jogl_libs@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

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

# ProM's GraphViz package unpacks a generic-linux dot under java.io.tmpdir and
# runs it; NixOS cannot exec that, so every graphviz view (Inductive visual
# Miner, ...) fails with "invalid dot given". Unpack the set ourselves -- ProM
# re-unpacks all of it as soon as one file is missing -- and swap linux64/dot
# for a wrapper around nixpkgs' dot. A fresh install only gets this on the
# launch after ProM has downloaded the package.
tmp="$data/tmp"
for gv in "$data"/packages/graphviz-*/GraphViz.jar; do
  [ -e "$gv" ] || continue
  constants=$(@jdk@/bin/javap -constants -cp "$gv" org.processmining.plugins.graphviz.dot.Dot2Image)
  [[ $constants =~ dotVersion\ =\ ([0-9]+) ]] || continue
  dots="$tmp/.prom-graphviz/dotBinaries${BASH_REMATCH[1]}"
  if [ ! -e "$dots/config6" ]; then
    staging=$(mktemp -d)
    (cd "$staging" && @jdk@/bin/jar xf "$gv" org/processmining/plugins/graphviz/dot/binaries)
    mkdir -p "$dots"
    cp -r "$staging"/org/processmining/plugins/graphviz/dot/binaries/. "$dots"/
    rm -rf "$staging"
  fi
  rm -f "$dots/linux64/dot"
  printf '#!%s\nexec %s "$@"\n' '@shell@' '@dot@' >"$dots/linux64/dot"
  chmod +x "$dots/linux64/dot"
done

classpath=
for jar in "$share"/dist/*.jar "$share"/lib/*.jar; do
  classpath="$classpath:$jar"
done

exec @jdk@/bin/java \
  -Xmx4G \
  -Duser.home="$data" \
  -Djava.io.tmpdir="$tmp" \
  -da \
  -classpath "${classpath#:}" \
  -Djava.library.path="$share/lib" \
  -Djava.system.class.loader=org.processmining.framework.util.ProMClassLoader \
  -Djava.util.Arrays.useLegacyMergeSort=true \
  org.processmining.contexts.uitopia.UI "$@"
