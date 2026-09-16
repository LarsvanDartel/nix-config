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
      # read these rather than carrying their own numbers. stylix reaches
      # foot/alacritty from `terminal`, and off that same value flips btop's and
      # helix's `transparent` flags — load-bearing: a TUI painting its own
      # opaque background punches a solid rectangle through the translucent
      # terminal. The niri shell's surfaces are wired by hand in
      # _noctalia/home.nix: stylix's noctalia-shell target is gated on
      # `options.programs ? noctalia-shell` and ours is a wrapped package, so
      # the target is inert. `applications` is deliberately 1.0 — a translucent
      # PDF is harder to read, and translucent browser chrome around opaque
      # content just looks broken.
      opacity = {
        terminal = 0.8;
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
