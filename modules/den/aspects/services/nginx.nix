# services.nginx — reverse proxy; includes the acme wildcard cert.
{den, ...}: {
  den.aspects.services.nginx = {
    includes = [den.aspects.services.acme];
    nixos = {
      config,
      pkgs,
      ...
    }: {
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

      # NoNewPrivileges unit: no exec transitions out of this profile.
      security.apparmor.policies.nginx = {
        inherit (config.cosmos.security.apparmor) state;
        profile = ''
          abi <abi/5.0>,
          include <tunables/global>

          profile nginx ${config.services.nginx.package}/bin/nginx flags=(attach_disconnected,mediate_deleted) {
            include <abstractions/base-strict>
            include <abstractions/nameservice>
            include <abstractions/ssl_certs>

            capability net_bind_service,
            capability sys_resource,

            network inet stream,
            network inet6 stream,
            network inet dgram,
            network inet6 dgram,
            network unix stream,

            ${config.services.nginx.package}/bin/nginx mr,
            @{sys}/devices/system/cpu/online r,

            /run/nginx/ rw,
            /run/nginx/** rwk,
            /var/log/nginx/ rw,
            /var/log/nginx/* rw,
            /var/cache/nginx/ rw,
            /var/cache/nginx/** rwkl,
            /tmp/ r,
            /tmp/nginx_*/ rw,
            /tmp/nginx_*/** rw,

            /var/lib/acme/*/ r,
            /var/lib/acme/*/{cert,chain,fullchain,key}.pem r,
            /run/phpfpm/*.sock rw,

            signal (send, receive) peer=nginx,
            signal (receive) peer=unconfined,

            deny /run/secrets{,.d}/** rwlkmx,
            deny /run/secrets-for-users{,.d}/** rwlkmx,
            deny /run/credentials/** rwlkmx,
            deny /persist/** rwlkmx,

            include if exists <local/nginx>
          }
        '';
      };

      # Build-time `nginx -t` on the real config: `validateConfigFile` only runs gixy, which accepts
      # invalid map variables that kill every vhost.
      system.checks = [
        (pkgs.runCommand "nginx-config-${config.networking.hostName}" {
            nativeBuildInputs = [config.services.nginx.package pkgs.openssl];
          } ''
            # Certificates load during the parse but ACME writes them at runtime: point every acme path
            # at a throwaway pair. Only the certificate paths differ from the shipped config.
            openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=check \
              -keyout key.pem -out cert.pem 2>/dev/null

            sed -e "s#/var/lib/acme/[^ ;\"]*key\.pem#$PWD/key.pem#g" \
                -e "s#/var/lib/acme/[^ ;\"]*\.pem#$PWD/cert.pem#g" \
              ${config.environment.etc."nginx/nginx.conf".source} > test.conf

            # Not the exit status: pid-file and access-log failures outside the sandbox follow the parse.
            result="$(nginx -t -c "$PWD/test.conf" 2>&1 || true)"
            echo "$result"

            if ! grep -q "syntax is ok" <<<"$result"; then
              echo >&2
              echo "nginx rejected the configuration above." >&2
              echo "It would fail its pre-start check and never start, taking" >&2
              echo "every vhost on this host down with it." >&2
              exit 1
            fi

            touch $out
          '')
      ];
    };
  };
}
