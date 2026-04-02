{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib.meta) getExe;
  inherit (lib.strings) replaceString concatLines optionalString;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.options) mkEnableOption mkPackageOption mkOption;
  inherit (lib.types) listOf package attrsOf path nullOr str;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.gaming.launchers.minecraft.waywall;

  programTable = concatLines (
    map (p: ''${replaceString "-" "_" p.pname} = "${getExe p}",'') cfg.config.programs
  );
  filesTable = concatLines (mapAttrsToList (k: v: ''${k} = "${v}",'') cfg.config.files);

  prelude =
    ''
      -- added by mcsr-nixos
    ''
    + optionalString cfg.config.enableWaywork ''
      package.path = package.path .. ";${pkgs.mcsr.waywork}/?.lua"
    ''
    + optionalString cfg.config.enableFloating ''
      package.path = package.path .. ";${pkgs.mcsr.floating}/?.lua"
    ''
    + optionalString (builtins.length cfg.config.programs != 0) ''
      local programs = {
      ${programTable}}
    ''
    + optionalString (builtins.length (builtins.attrNames cfg.config.files) != 0) ''
      local files = {
      ${filesTable}}
    ''
    + ''
      -- end mcsr-nixos
    '';

  finalCfg =
    prelude
    + (
      if cfg.config.source != null
      then builtins.readFile cfg.config.source
      else cfg.config.text
    );
in {
  options.cosmos.gaming.launchers.minecraft.waywall = {
    enable = mkEnableOption "waywall";
    package = mkPackageOption pkgs "waywall" {};

    config = {
      enableWaywork = mkEnableOption "waywork";
      enableFloating = mkEnableOption "floating";

      programs = mkOption {
        type = listOf package;
        default = [];
      };

      files = mkOption {
        type = attrsOf path;
        default = {};
      };

      source = mkOption {
        type = nullOr path;
        description = "Path to the lua config file for waywall.";
        default = null;
      };

      text = mkOption {
        type = nullOr str;
        description = "Contents of the lua config file for waywall.";
        default = null;
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.config.source == null) != (cfg.config.text == null);
      }
    ];

    home.file.".config/waywall/init.lua".text = finalCfg;

    home.packages = [cfg.package];
  };
}
