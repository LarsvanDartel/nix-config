{
  config,
  lib,
  ...
}: let
  cfg = config.modules.yubico;
in {
  options.modules.yubico = {
    enable = lib.mkEnableOption "yubico";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".yubico"
    ];
  };
}
