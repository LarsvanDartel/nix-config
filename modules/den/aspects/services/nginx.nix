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

      # Build-time `nginx -t` on the real config. `validateConfigFile` only runs
      # gixy, which once accepted an invalid map variable that killed every vhost.
      # nginx's exit status is useless in the sandbox; grep for "syntax is ok".
      system.checks = [
        (pkgs.runCommand "nginx-config-${config.networking.hostName}" {
            nativeBuildInputs = [config.services.nginx.package pkgs.openssl];
          } ''
            # Certificates are loaded during the parse, before "syntax is ok" is
            # printed — so on a TLS-terminating host a missing one is
            # indistinguishable from a broken config. They cannot be present
            # here: ACME writes them at runtime and /var/lib is not creatable by
            # nixbld. So point every acme path at a throwaway pair instead.
            #
            # This is the one place the file under test is not the file that
            # ships. Only the certificate paths differ; every directive, variable
            # and block is the real one, which is what this is checking.
            openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=check \
              -keyout key.pem -out cert.pem 2>/dev/null

            sed -e "s#/var/lib/acme/[^ ;\"]*key\.pem#$PWD/key.pem#g" \
                -e "s#/var/lib/acme/[^ ;\"]*\.pem#$PWD/cert.pem#g" \
              ${config.environment.etc."nginx/nginx.conf".source} > test.conf

            # Never trusted for its exit status: the pid file and the access log
            # live outside the sandbox too, and those failures come *after* the
            # parse, so the status is non-zero even for a perfectly good config.
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
