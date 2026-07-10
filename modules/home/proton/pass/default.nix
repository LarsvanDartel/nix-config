{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.proton.pass;
in {
  options.cosmos.proton.pass = {
    enable = mkEnableOption "Proton Pass (desktop app)";
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.proton-pass];

    cosmos.system.impermanence.persist.directories = [".config/Proton Pass"];
  };
}
