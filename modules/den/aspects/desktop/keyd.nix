# desktop.keyd — tap/hold on the Mod key, and Mod + the digit row sent as
# layout-independent keys. niri cannot bind a bare modifier tap, and neither
# compositor binds keycodes; keyd works at evdev level below xkb.
# keyd grabs every keyboard; escape hatch is backspace+escape+enter.
{...}: {
  den.aspects.desktop.keyd.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf str;

    cfg = config.cosmos.desktops.input.modTap;

    # Spare keycodes whose XKB keysyms are XF86Launch1..9 in every layout.
    workspaceKeycodes = ["prog1" "prog2" "prog3" "prog4" "f14" "f15" "f16" "f17" "f18"];
    digitRow = mods:
      lib.listToAttrs (lib.imap1 (i: key: lib.nameValuePair (toString i) "${mods}-${key}") workspaceKeycodes);
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

    options.cosmos.desktops.input.workspaceKeysyms = mkOption {
      type = listOf str;
      readOnly = true;
      default = map (i: "XF86Launch${toString i}") (lib.range 1 9);
      description = ''
        What Mod + the physical digit keys 1..9 arrive as (element N is key N),
        for the compositors' workspace binds. Both bind only keysyms, and the
        printed symbols collide across layouts: us(dvp)'s Shift turns its [ key
        into 7, so Mod+Shift+[ matched a us(intl) Mod+Shift+7 bind. keyd sends
        prog1..4 and f14..f18, which xkeyboard-config maps to XF86Launch1..9
        in every layout:

          nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap \
            --layout us --variant dvp | grep -E '<(I156|I157|I210|I211|FK1[4-8])>'
      '';
    };

    config.services.keyd = {
      enable = true;
      keyboards.default.settings = {
        main = {
          # `overload` emits the tap key only if no other key was pressed meanwhile.
          leftmeta = "overload(meta, ${cfg.key})";
        };
        # A modifier layer's bindings drop its modifier, so name it again.
        meta = digitRow "M";
        "meta+shift" = digitRow "M-S";
      };
    };
  };
}
