{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.strings) hasSuffix;

  cfg = config.cosmos.desktops.common.styling;

  nonDefault = dir:
    map (n: dir + "/${n}")
    (builtins.attrNames (filterAttrs (n: t: t == "regular" && n != "default.nix" && hasSuffix ".nix" n) (builtins.readDir dir)));
in {
  imports =
    (nonDefault ./.)
    ++ [
      ./fonts
      ./icons
      ./themes
    ];

  options.cosmos.desktops.common.styling = {
    # Internal: on when the styling feature is imported (parts self-gate on it).
    enable = mkEnableOption "styling configuration" // {default = true;};
  };

  config = mkIf cfg.enable {
    # stylix drives the cursor via home.pointerCursor; opt in explicitly to
    # silence the deprecation (required once abort-on-warn is on).
    home.pointerCursor.enable = lib.mkDefault true;

    stylix = {
      enable = true;
      autoEnable = true;
      # One source of truth for how see-through the desktop is; both shells
      # read these rather than carrying their own numbers.
      #
      # stylix reaches only some of it directly — foot and alacritty from
      # `terminal`, and off that same value it flips btop's and helix's
      # `transparent` flags. That coupling is why `terminal` is 1.0: a
      # translucent terminal makes every TUI that paints its own background
      # punch a solid rectangle through it, and text over a moving wallpaper
      # is the one place the effect costs more legibility than it buys. The
      # shells still get their translucency from `desktop`/`popups`, which
      # carry no text you read for minutes at a time. The niri shell's surfaces
      # are wired up by hand in _noctalia/home.nix, because stylix's
      # noctalia-shell target is gated on `options.programs ? noctalia-shell`
      # and ours is a wrapped package, not that home-manager module — so the
      # target is inert and the values have to be threaded through manually.
      #
      # `applications` is deliberately left at 1.0. It reaches zathura and zen,
      # and a translucent PDF is simply harder to read, while a translucent
      # browser chrome wrapped around opaque page content just looks broken.
      opacity = {
        terminal = 1.0;
        desktop = 0.8;
        popups = 0.8;
      };

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
