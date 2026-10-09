# desktop.keyd — tap/hold on the Mod key. niri (and Hyprland) cannot bind a
# bare modifier tap; keyd resolves tap-vs-hold at evdev level below xkb.
# keyd grabs every keyboard; escape hatch is backspace+escape+enter.
{...}: {
  den.aspects.desktop.keyd.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;

    cfg = config.cosmos.desktops.input.modTap;
  in {
    options.cosmos.desktops.input.modTap = {
      key = mkOption {
        type = str;
        default = "f19";
        description = ''
          Key emitted when Mod is tapped rather than held, in keyd's (evdev)
          naming. Must be something no physical keyboard here produces.

          f19 rather than f13, because of `keysym` below.
        '';
      };

      keysym = mkOption {
        type = str;
        default = lib.toUpper cfg.key;
        description = ''
          The same key under its XKB name, which is what compositors bind on.

          These are NOT interchangeable. xkeyboard-config's `pc` symbols hand
          most of the F13..F24 keycodes to multimedia keysyms instead of naming
          them after themselves — f13 is XF86Tools, f14..f18 are XF86Launch5..9,
          f20 is XF86AudioMicMute, f21/f22 are the touchpad toggles. f19 is the
          one in that range that actually produces `F19`, which is why it is the
          default. Change `key` and you will probably have to set this too:

            nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap \
              --layout us --variant dvp | grep '<FK19>'
        '';
      };
    };

    config.services.keyd = {
      enable = true;
      keyboards.default.settings.main = {
        # `overload` emits the tap key only if no other key was pressed meanwhile.
        leftmeta = "overload(meta, ${cfg.key})";
      };
    };
  };
}
