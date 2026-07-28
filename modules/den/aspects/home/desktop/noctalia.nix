# home.noctalia — the noctalia shell (bar, launcher, notifications, lock screen,
# control centre) as ONE compositor-agnostic, WRAPPED package.
#
# Config is baked into the derivation by `nix-wrapper-modules`' noctalia-shell
# wrapper: NOCTALIA_SETTINGS_FILE points at the generated store file, so nix is
# authoritative and a rebuild applies immediately. noctalia's settings panel
# therefore cannot save — settings are edited here. The rest of its config dir
# (colors.json, colorschemes/, plugins/) stays writable in ~/.config/noctalia.
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
