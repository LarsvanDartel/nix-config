{...}: {
  # Optional: the `networking` base config it depends on comes from the `common`
  # aggregate, which every host imports.
  flake.modules.nixos.dnscrypt = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) port;
    inherit (lib.modules) mkIf mkMerge mkForce;

    cfg = config.cosmos.networking.dnscrypt;
  in {
    options.cosmos.networking.dnscrypt = {
      port = mkOption {
        type = port;
        default = 53;
      };
    };

    config = mkMerge [
      {
        # Resolve through the local dnscrypt-proxy listener.
        networking.nameservers = mkForce ["::1"];

        # See https://wiki.nixos.org/wiki/Encrypted_DNS
        services.dnscrypt-proxy = {
          enable = true;
          settings = {
            listen_addresses = ["[::1]:${toString cfg.port}"];
            sources.public-resolvers = {
              urls = [
                "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
              ];
              minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
            };

            ipv6_servers = true;
            block_ipv6 = false;

            require_dnssec = true;
            require_nolog = false;
            require_nofilter = true;
          };
        };

        systemd.services.dnscrypt-proxy.serviceConfig.StateDirectory = "dnscrypt-proxy";
      }
      (mkIf (cfg.port != 53) {
        # Forward loopback traffic on port 53 to dnscrypt-proxy2.
        networking.firewall.extraCommands = ''
          ip6tables --table nat --flush OUTPUT
          ${lib.flip (lib.concatMapStringsSep "\n") ["udp" "tcp"] (proto: ''
            ip6tables --table nat --append OUTPUT \
              --protocol ${proto} --destination ::1 --destination-port 53 \
              --jump REDIRECT --to-ports ${toString cfg.port}
          '')}
        '';
      })
    ];
  };
}
