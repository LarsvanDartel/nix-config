# The niri home config, as a plain home-manager module *factory*: imported by
# BOTH `den.aspects.home.niri` (see ../../home/desktop/niri.nix) and voyager's
# `specialisation.niri` (specialisation bodies cannot `include` a den aspect).
# Call as `import ./_niri/home.nix {}`.
{}: {
  lib,
  osConfig,
  pkgs,
  ...
}: let
  niri = osConfig.programs.niri.package;

  # nix-wrapper-modules quotes every KDL node name and property key. niri reads
  # that fine, but the hand-rolled text parsers reading a niri config do not:
  # noctalia's keybind-cheatsheet gives up at `line.startsWith("binds")`, finds
  # nothing and never finishes loading. Unquoting the leading token of each
  # line and the property keys yields the conventional spelling; running
  # `niri validate` on the result is what makes this safe rather than a hopeful
  # regex — the build fails instead of publishing a config that lies about what
  # niri is running.
  readableConfig = pkgs.runCommand "niri-config.kdl" {} ''
    sed -E \
      -e 's/^([[:space:]]*)"([^"]+)"/\1\2/' \
      -e 's/"([A-Za-z0-9_-]+)"=/\1=/g' \
      ${niri}/niri-config.kdl > $out
    ${lib.getExe niri} validate --config $out
  '';
in {
  home.packages = with pkgs; [
    playerctl
    wl-clipboard
  ];

  cosmos.system.impermanence.persist.directories = ["Pictures/screenshots"];

  # The wrapped niri gets its config via NIRI_CONFIG from the store, so
  # ~/.config/niri/config.kdl is never consulted and normally does not exist —
  # but tooling assumes the conventional path, so publish it there (regenerated
  # and validated every rebuild).
  xdg.configFile."niri/config.kdl".source = readableConfig;
}
