# services.nginx + services.acme. nginx includes acme (the *.lvdar.nl wildcard).
{den, ...}: {
  den.aspects.services.acme.nixos = {config, ...}: {
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
        credentialFiles.CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets."keys/cloudflare/dns".path;
      };
      certs."lvdar.nl" = {
        domain = "*.lvdar.nl";
        extraDomainNames = ["lvdar.nl"];
      };
    };
  };

  den.aspects.services.nginx = {
    includes = [den.aspects.services.acme];
    nixos = {...}: {
      networking.firewall.allowedTCPPorts = [80 443];
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
  };
}
