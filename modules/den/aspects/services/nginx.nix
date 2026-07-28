# services.nginx — reverse proxy; includes the acme wildcard cert.
{den, ...}: {
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
