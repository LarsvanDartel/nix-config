{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.nginx;
in {
  options.cosmos.services.nginx = {
    enable = mkEnableOption "nginx";
  };

  config = mkIf cfg.enable {
    sops.secrets."keys/cloudflare/dns" = {};
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "admin@lvdar.nl";
        dnsProvider = "cloudflare";
        credentialFiles = {
          CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets."keys/cloudflare/dns".path;
        };
      };

      certs."lvdar.nl" = {
        domain = "*.lvdar.nl";
        extraDomainNames = ["lvdar.nl"];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [80 443];
    };

    users.users.nginx.extraGroups = ["acme"];

    services.nginx = {
      enable = true;
      package = pkgs.nginxStable.override {openssl = pkgs.libressl;};
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";
    };
  };
}
