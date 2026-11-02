# The niri home config, as a plain home-manager module factory imported by its
# aspect `den.aspects.home.niri`.
{cosmosStyling}: {
  config,
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

  # The colours of desktop/_niri/system.nix in one mode; its config includes
  # the current mode's copy last. The shadow stays the darkest shade.
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

  # The wrapped niri reads its config from the store; publish it at the
  # conventional path for tooling.
  xdg.configFile."niri/config.kdl".source = readableConfig;
}
