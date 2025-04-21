{
  config,
  lib,
  ...
}: let
  cfg = config.modules.firewall;
in {
  options.modules.firewall = {
    enable = lib.mkEnableOption "firewall";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.enable = true;
  };
}
