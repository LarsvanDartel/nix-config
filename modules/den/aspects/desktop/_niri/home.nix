# home.niri — home-manager body of the niri aspect: readable config.kdl and per-mode colours.
{cosmosStyling}: {
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  niri = osConfig.programs.niri.package;

  # nix-wrapper-modules quotes every KDL name, which breaks naive parsers (keybind-cheatsheet).
  # Unquote, then `niri validate` so a wrong config fails the build.
  readableConfig = pkgs.runCommand "niri-config.kdl" {} ''
    sed -E \
      -e 's/^([[:space:]]*)"([^"]+)"/\1\2/' \
      -e 's/"([A-Za-z0-9_-]+)"=/\1=/g' \
      ${niri}/niri-config.kdl > $out
    ${lib.getExe niri} validate --config $out
  '';

  # desktop/_niri/system.nix's colours in one mode; its config includes the current mode's copy last.
  colorsFor = mode: let
    c = config.cosmos.desktops.common.styling.modes.rendered.${mode}.lib.stylix.colors.withHashtag;
    shade =
      if mode == "dark"
      then c.base00
      else c.base07;
  in
    pkgs.runCommand "niri-colors-${mode}.kdl" {
      kdl = ''
        layout {
            focus-ring {
                active-color "${c.${cosmosStyling.accent}}"
                inactive-color "${c.base02}"
            }
            shadow {
                color "${shade}a0"
            }
        }
        window-rule {
            match is-window-cast-target=true
            focus-ring {
                active-color "${c.base08}"
                inactive-color "${c.base08}80"
            }
            tab-indicator {
                active-color "${c.base08}"
                inactive-color "${c.base08}80"
            }
        }
      '';
      passAsFile = ["kdl"];
    } ''
      cp "$kdlPath" $out
      ${lib.getExe niri} validate --config $out
    '';
in {
  cosmos.desktops.common.styling.modes.files."niri.kdl" = colorsFor;

  home.packages = with pkgs; [
    playerctl
    wl-clipboard
  ];

  cosmos.system.impermanence.persist.directories = ["Pictures/screenshots"];

  xdg.configFile."niri/config.kdl".source = readableConfig;
}
