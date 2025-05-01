{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.fingerprint;
in {
  options.modules.fingerprint = {
    enable = mkEnableOption "fingerprint reader support";
  };

  config = mkIf cfg.enable {
    modules.persist.directories = ["/var/lib/fprint"];

    # Enable the fingerprint reader service
    systemd.services.fprintd = {
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "simple";
    };

    # Enable the fprintd service
    services.fprintd.enable = true;
  };
}
