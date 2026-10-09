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
    enable = mkEnableOption "styling configuration" // {default = true;};
  };

  config = mkIf cfg.enable {
    # Required under abort-on-warn: silences stylix's cursor deprecation.
    home.pointerCursor.enable = lib.mkDefault true;

    stylix = {
      enable = true;
      autoEnable = true;
      # Load-bearing: `terminal` also flips btop's/helix's `transparent`, or a
      # TUI paints an opaque rectangle through the terminal. noctalia reads these
      # by hand (_noctalia/home.nix). `applications` stays 1.0 deliberately.
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
