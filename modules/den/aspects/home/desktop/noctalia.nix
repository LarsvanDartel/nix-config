# home.noctalia — the noctalia shell (bar, launcher, notifications, lock screen,
# control centre) as ONE compositor-agnostic, WRAPPED package.
#
# Config is baked into the derivation by `nix-wrapper-modules`' noctalia-shell
# wrapper. noctalia's settings panel is a GUI that rewrites its own config, so a
# pure store config would be read-only; `outOfStoreConfig` + `autoCopyConfig`
# seed our declarative look into a writable dir on first start (never
# overwriting what is already there), keeping the GUI usable.
#
# Started by a systemd user service bound to `graphical-session.target`, which
# both niri (niri.service) and Hyprland (UWSM) reach — so this one aspect serves
# either compositor, with no exec-once/spawn-at-startup duplication.
#
# The body lives in ./_noctalia/home.nix so voyager's `specialisation.niri` can
# apply the same content (specialisation bodies are plain modules and cannot
# `include` a den aspect).
{inputs, ...}: {
  den.aspects.home.noctalia.homeManager = import ./_noctalia/home.nix {inherit inputs;};
}
