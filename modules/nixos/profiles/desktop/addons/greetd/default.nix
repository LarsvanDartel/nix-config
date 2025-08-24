{
  config,
  lib,
  ...
}: let
  inherit (lib.custom) get-non-default-nix-files;
  inherit (lib.types) str;
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.desktop.addons.greetd;
in {
  imports = get-non-default-nix-files ./.;

  options.profiles.desktop.addons.greetd = {
    enable = mkEnableOption "greetd";
    command = mkOption {
      type = str;
      default = "";
      description = "Command to run to show greeter";
    };
  };

  config = mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = rec {
        default_session = {
          inherit (cfg) command;
          user = config.user.name;
        };
        initial_session = default_session;
      };
    };
  };
}
