# home.theme-options — the runtime light/dark schema, declared in every home
# (roles.home-base) so any program can contribute its per-mode files and
# repaint step; home.theme (desktop.styling) does the switching.
{cosmosStyling, ...}: {
  den.aspects.home.theme-options.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) attrsOf functionTo path lines listOf str lazyAttrsOf raw package;
    cfg = config.cosmos.desktops.common.styling.modes;
  in {
    options.cosmos.desktops.common.styling.modes = {
      enable = mkEnableOption "runtime light/dark switching (set by home.theme; off inside its per-mode renders)";

      current = mkOption {
        type = str;
        readOnly = true;
        default = "${config.home.homeDirectory}/${cosmosStyling.stateDir}/current";
        description = "Link to the session's mode: `dark` or `light`, each that mode's file farm.";
      };

      modal = mkOption {
        type = raw;
        readOnly = true;
        # Homes without home.theme (servers) never switch: one build, no dispatcher.
        default = name: mk:
          if cfg.enable
          then cosmosStyling.modal pkgs name mk
          else mk cosmosStyling.defaultMode;
        description = "`name: mk:` a program whose config bakes in colours, per mode where switching is on (cosmosStyling.modal).";
      };

      files = mkOption {
        type = attrsOf (functionTo path);
        default = {};
        description = ''
          Extra per-mode files in the farm, by name, as a function of the mode.
          Configs include them as ~/${cosmosStyling.stateDir}/current/<name>.
        '';
      };

      onSwitch = mkOption {
        type = lines;
        default = "";
        description = ''
          Shell run by `theme` after switching, to repaint running programs;
          $mode and $farm (that mode's files) are set. Must not fail when the
          program is not running.
        '';
      };

      exclude = mkOption {
        type = listOf str;
        default = [];
        description = "Home file target prefixes kept out of the farm (their owner switches itself).";
      };

      rendered = mkOption {
        type = lazyAttrsOf raw;
        readOnly = true;
        internal = true;
        description = "This home's config rendered in each mode (home.theme).";
      };

      package = mkOption {
        type = package;
        readOnly = true;
        description = "The `theme` command (home.theme).";
      };
    };
  };
}
