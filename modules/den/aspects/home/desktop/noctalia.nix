# home.noctalia — the noctalia shell (bar, launcher, notifications, lock
# screen, control centre) as one compositor-agnostic, WRAPPED package.
# Settings are baked into the derivation (NOCTALIA_SETTINGS_FILE), so
# noctalia's settings panel cannot save — edit config here; the rest of
# ~/.config/noctalia stays writable. Runs via one systemd user service on
# graphical-session.target that both niri and Hyprland (UWSM) reach. Body in
# ./_noctalia/home.nix so voyager's `specialisation.niri` can reuse it
# (specialisation bodies cannot `include` a den aspect).
{inputs, ...}: {
  den.aspects.home.noctalia.homeManager = import ./_noctalia/home.nix {inherit inputs;};
}
