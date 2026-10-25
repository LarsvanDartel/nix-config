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

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
