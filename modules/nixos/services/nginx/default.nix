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

      virtualHosts."whoami.lvdar.nl" = {
        forceSSL = true;
        enableACME = false;
        sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
        sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";

        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:8080";
          };

          "/vouch-validate" = {
            proxyPass = "http://[::1]:30746/validate";
            extraConfig = ''
              proxy_pass_request_body off; # no need to send the POST body

              proxy_set_header Content-Length "";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # these return values are passed to the @error401 call
              auth_request_set $auth_resp_jwt $upstream_http_x_vouch_jwt;
              auth_request_set $auth_resp_err $upstream_http_x_vouch_err;
              auth_request_set $auth_resp_failcount $upstream_http_x_vouch_failcount;
            '';
          };

          "@error401" = {
            return = "302 https://login.lvdar.nl/login?url=https://$http_host$request_uri&vouch-failcount=$auth_resp_failcount&X-Vouch-Token=$auth_resp_jwt&error=$auth_resp_err";
          };
        };
        extraConfig = ''
          auth_request /vouch-validate;
          error_page 401 = @error401;
        '';

        # If the user is not logged in, redirect them to Vouch's login URL
      };
    };

    services.whoami = {
      enable = true;
      port = 8080;
    };
  };
}
