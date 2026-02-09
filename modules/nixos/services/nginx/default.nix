{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.services.nginx;
in {
  options.cosmos.services.nginx = {
    enable = mkEnableOption "nginx";
    acme.enable = mkEnableOption "acme certs";
  };

  config = mkMerge [
    (mkIf (cfg.enable || cfg.acme.enable) {
      cosmos.system.impermanence.persist.directories = [
        {
          directory = "/var/lib/acme";
          user = "acme";
          group = "acme";
          mode = "0750";
        }
      ];

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
    })
    (mkIf cfg.enable {
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
    })
  ];
}
