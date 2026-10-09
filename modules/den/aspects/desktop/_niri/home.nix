# The niri home config, as a plain home-manager module factory shared by
# `den.aspects.home.niri` and voyager's `specialisation.niri`.
{}: {
  lib,
  osConfig,
  pkgs,
  ...
}: let
  niri = osConfig.programs.niri.package;

  # nix-wrapper-modules quotes every KDL name/key, which breaks naive parsers
  # (noctalia's keybind-cheatsheet never loads). Unquote, then `niri validate`
  # so the build fails rather than publishing a wrong config.
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

  # The wrapped niri reads its config from the store; publish it at the
  # conventional path for tooling.
  xdg.configFile."niri/config.kdl".source = readableConfig;
}
