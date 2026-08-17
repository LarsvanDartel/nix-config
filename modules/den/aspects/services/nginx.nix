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

      # Ask nginx whether it will accept the configuration, at build time.
      #
      # `services.nginx.validateConfigFile` does not do this, whatever its name
      # suggests. It runs pkgs.writers.writeNginxConfig, which is a formatter
      # plus gixy — a *security* linter looking for SSRF, host-header spoofing
      # and add_header inheritance. gixy parses with its own parser and has no
      # opinion on whether a directive is valid.
      #
      # The gap is not theoretical. `map $http_x_netbird_groups mc_may_smp {`
      # (a map assigns to a $variable, so the name needs the $) passed the whole
      # build and every check, then failed nginx's own parser at start:
      #
      #   nginx: [emerg] invalid variable name "mc_may_hardcore"
      #
      # A refused config means nginx does not start at all, so on endeavour that
      # took out jellyfin, immich, opencloud and kanidm's frontend together, and
      # the first sign of it was a service being down rather than a build going
      # red.
      #
      # Two details make this work in a sandbox, and both are load-bearing:
      #
      #   * nginx prints "syntax is ok" as soon as the parse succeeds, before it
      #     opens the pid file or the logs. Those live outside the sandbox and
      #     cannot be created — the builder is nixbld, not root — so the exit
      #     status is failure even for a good config and is worthless here. The
      #     presence of that line is the signal, and a config nginx rejects
      #     never produces it. Certificates are NOT in that category; see the
      #     openssl call below for what they cost.
      #   * interpolating the config derivation brings its references along, so
      #     the mime.types, fastcgi.conf and proxy-header snippets it includes
      #     are in the sandbox. Copying the file in by path instead loses them
      #     and the test fails on a missing include rather than on the config.
      #
      # It comes from environment.etc because upstream's `configFile` is a let
      # binding with no option in front of it; etc is where the module puts the
      # same derivation (nginx/default.nix:1694).
      #
      # In system.checks rather than the closure proper: it gates the build
      # without shipping anything to the host.
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
