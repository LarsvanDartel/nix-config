{config, ...}: let
  inherit (config.flake.modules.nixos) acme;
in {
  flake.modules.nixos.nginx = {...}: {
    imports = [acme];

    networking.firewall = {
      allowedTCPPorts = [80 443];
    };

    users.users.nginx.extraGroups = ["acme"];

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";
    };
  };
}
