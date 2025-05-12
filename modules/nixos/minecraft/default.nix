{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.minecraft;
in {
  imports = [inputs.nix-minecraft.nixosModules.minecraft-servers];

  options.modules.minecraft = {
    enable = mkEnableOption "Enable Minecraft server";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      inputs.nix-minecraft.overlay
      inputs.modpack-create.overlay
    ];

    modules.persist.directories = ["/srv/minecraft"];
    services.minecraft-servers = {
      enable = true;
      eula = true;
      openFirewall = true;
      servers.create = {
        enable = true;

        package = pkgs.fabricServers.fabric-1_20_1.override {
          loaderVersion = "0.16.14";
        };

        symlinks = {
          mods = "${pkgs.modpack-create.server}/mods";
        };

        serverProperties = {
          difficulty = 3;
          gamemode = 1;
        };
      };
    };
  };
}
