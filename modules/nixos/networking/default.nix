{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) listOf str port;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.networking;
in {
  options.cosmos.networking = {
    enable = mkEnableOption "networking";
    networkmanager.enable = mkEnableOption "networkmanager";
    nameservers = mkOption {
      type = listOf str;
      default = ["9.9.9.9"];
    };
    dnscrypt = {
      enable = mkEnableOption "dnscrypt";
      port = mkOption {
        type = port;
        default = 53;
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      networking = {
        enableIPv6 = true;
        firewall.enable = true;
        nameservers =
          if cfg.dnscrypt.enable
          then ["::1"]
          else cfg.nameservers;
      };
    })
    (mkIf cfg.networkmanager.enable {
      cosmos.system.impermanence.persist.directories = ["/etc/NetworkManager"];
      cosmos.user.extraGroups = ["networkmanager"];
      networking.networkmanager = {
        enable = true;
        plugins = [pkgs.networkmanager-openvpn];
        dns = "none";
      };
    })
    (mkIf cfg.dnscrypt.enable {
      # See https://wiki.nixos.org/wiki/Encrypted_DNS
      services.dnscrypt-proxy = {
        inherit (cfg.dnscrypt) enable;
        settings = {
          listen_addresses = ["[::1]:${toString cfg.dnscrypt.port}"];
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

          # server_names = ["quad9-dnscrypt-ip6-nofilter-pri" "quad9-dnscrypt-ip4-nofilter-pri"];
        };
      };

      systemd.services.dnscrypt-proxy.serviceConfig.StateDirectory = "dnscrypt-proxy";
    })
    (mkIf (cfg.dnscrypt.enable && cfg.dnscrypt.port != 53) {
      # Forward loopback traffic on port 53 to dnscrypt-proxy2.
      networking.firewall.extraCommands = ''
        ip6tables --table nat --flush OUTPUT
        ${lib.flip (lib.concatMapStringsSep "\n") ["udp" "tcp"] (proto: ''
          ip6tables --table nat --append OUTPUT \
            --protocol ${proto} --destination ::1 --destination-port 53 \
            --jump REDIRECT --to-ports ${toString cfg.dnscrypt.port}
        '')}
      '';
    })
  ];
}
