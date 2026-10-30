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

    # Mod + digit key N is sent as key N here: keyd's name, and the XKB keysym it
    # arrives as in every layout. keyd's names are its own, not the kernel's:
    # its prog1..4 are F21..F24 (touchpad keysyms), and it spends KEY_PROG1..4
    # (XF86Launch1..4) on scroll events, so those cannot be sent at all.
    workspaceKeys = [
      {
        keyd = "scale";
        keysym = "XF86LaunchA";
      }
      {
        keyd = "dashboard";
        keysym = "XF86LaunchB";
      }
      {
        keyd = "msdos";
        keysym = "XF86DOS";
      }
      {
        keyd = "finance";
        keysym = "XF86Finance";
      }
      {
        keyd = "f14";
        keysym = "XF86Launch5";
      }
      {
        keyd = "f15";
        keysym = "XF86Launch6";
      }
      {
        keyd = "f16";
        keysym = "XF86Launch7";
      }
      {
        keyd = "f17";
        keysym = "XF86Launch8";
      }
      {
        keyd = "f18";
        keysym = "XF86Launch9";
      }
    ];
    digitRow = mods:
      lib.listToAttrs (lib.imap1 (i: key: lib.nameValuePair (toString i) "${mods}-${key.keyd}") workspaceKeys);
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
      default = map (key: key.keysym) workspaceKeys;
      description = ''
        What Mod + the physical digit keys 1..9 arrive as (element N is key N),
        for the compositors' workspace binds. Both bind only keysyms, and the
        printed symbols collide across layouts: us(dvp)'s Shift turns its [ key
        into 7, so Mod+Shift+[ matched a us(intl) Mod+Shift+7 bind. keyd sends
        keys that no keyboard here has and that xkeyboard-config maps the same
        in every layout (`workspaceKeys` above). To check one, look up its
        evdev code in keyd's src/keys.h and the keysym at that code + 8:

          nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap \
            --layout us --variant dvp | grep -E '<I128>|= 128;'
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
