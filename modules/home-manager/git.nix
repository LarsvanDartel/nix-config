{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.git;
in {
  options.git = {
    enable = lib.mkEnableOption "Enable Git";
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      userName = "LarsvanDartel";
      userEmail = "larsvandartel73@gmail.com";
    };
  };
}
