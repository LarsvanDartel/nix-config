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
      opacity.terminal = 1.0;

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
