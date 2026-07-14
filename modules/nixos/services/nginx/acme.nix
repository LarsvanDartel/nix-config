# ACME wildcard cert for *.lvdar.nl via Cloudflare DNS. Split from the nginx
# feature so services that only need the cert (or nginx) can pull it in.
{...}: {
  flake.modules.nixos.acme = {config, ...}: {
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
  };
}
