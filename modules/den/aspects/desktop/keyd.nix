# desktop.keyd — tap/hold on the Mod key.
#
# niri cannot bind a modifier on its own. `find_configured_bind` compares a
# bind's modifiers against the xkb state *after* the current key is folded in,
# so on a Super_L press `logo` is already set: a bare `Super_L` bind never
# matches, and `Mod+Super_L` matches on key-DOWN — which would fire before every
# Super shortcut you type. Hyprland's `bindr` has the same press/release
# limitation in reverse.
#
# keyd sits below xkb, at evdev level, and resolves tap-vs-hold before the
# compositor ever sees the key: hold Super and it is Meta as always, tap it
# alone and it emits a key nothing else uses. The compositor then binds that key
# like any other.
#
# Because keyd grabs every keyboard, a broken config can leave you unable to
# type. Its escape hatch is chording backspace+escape+enter, which terminates
# keyd and restores the raw devices.
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
        default = "f13";
        description = ''
          Key emitted when Mod is tapped rather than held, in keyd's (evdev)
          naming. Must be something no physical keyboard here produces —
          f13..f24 are the usual choice.
        '';
      };

      keysym = mkOption {
        type = str;
        readOnly = true;
        default = lib.toUpper cfg.key;
        description = ''
          The same key under its XKB name, which is what compositors bind on.
          Holds for f13..f24; anything else would need spelling out.
        '';
      };
    };

    config.services.keyd = {
      enable = true;
      keyboards.default.settings.main = {
        # `overload` activates the meta layer while held and emits the tap key
        # on release, but only if no other key was pressed meanwhile — so
        # Mod+L, Mod+Tab and the workspace binds are untouched.
        leftmeta = "overload(meta, ${cfg.key})";
      };
    };
  };
}
