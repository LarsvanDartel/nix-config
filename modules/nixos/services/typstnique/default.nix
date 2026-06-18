{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.typstnique;
in {
  imports = [inputs.typstnique.nixosModules.default];

  options.cosmos.services.typstnique = {
    enable = mkEnableOption "typstnique";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
    };
  };
}
