# The niri home config, as a plain home-manager module *factory*.
#
# Imported by BOTH `den.aspects.home.niri` (see ../../home/desktop/niri.nix) and
# voyager's `specialisation.niri` — specialisation bodies are ordinary NixOS
# modules and cannot `include` a den aspect, so the shared content lives here.
# Call it as `import ./_niri/home.nix {}`.
{}: {
  osConfig,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    playerctl
    wl-clipboard
  ];

  cosmos.system.impermanence.persist.directories = ["Pictures/screenshots"];

  # The wrapped niri is handed its config through NIRI_CONFIG, pointing into the
  # store, so ~/.config/niri/config.kdl is never consulted and normally does not
  # exist. Plenty of tooling assumes the conventional path anyway — noctalia's
  # keybind-cheatsheet parses it as a *file* under niri (only the Hyprland path
  # asks the compositor, via `hyprctl binds -j`) and sits there waiting when it
  # is missing, which is what made the cheatsheet time out.
  #
  # Publishing the very same file there fixes that class of problem outright and
  # cannot drift: it is the exact store path niri itself booted with, read-only,
  # regenerated on every rebuild.
  xdg.configFile."niri/config.kdl".source = "${osConfig.programs.niri.package}/niri-config.kdl";
}
