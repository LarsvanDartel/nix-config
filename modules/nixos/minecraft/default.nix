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

    host.sudo-groups = ["minecraft"];
    services.minecraft-servers = {
      enable = true;
      eula = true;
      openFirewall = true;

      servers.create = {
        enable = true;

        package = pkgs.neoForgeServers.neoforge-21_1_172;
        jvmOpts = "-Xms6144M -Xmx8192M";

        symlinks = {
          mods = "${pkgs.modpack-create.server}/mods";
        };

        serverProperties = {};
      };
    };
  };
}
