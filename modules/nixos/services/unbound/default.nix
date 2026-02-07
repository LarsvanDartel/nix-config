{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) port str nullOr;
  inherit (lib.lists) optional;

  cfg = config.cosmos.services.unbound;
in {
  options.cosmos.services.unbound = {
    enable = mkEnableOption "unbound";
    port = mkOption {
      type = port;
      default = 53;
      description = "Port for Unbound DNS service";
    };
    blocklist = mkOption {
      type = nullOr str;
      default = null;
      description = "File to use for DNS blocking";
    };
    dns64 = {
      enable = mkEnableOption "dns64";
      prefix = mkOption {
        type = str;
        default = "64:ff9b::/96";
      };
    };
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      "/var/lib/unbound"
    ];
    cosmos.networking = {
      dnscrypt.port = mkDefault 51;
    };
    services.unbound = {
      enable = true;
      resolveLocalQueries = !config.cosmos.networking.dnscrypt.enable;
      settings = mkMerge [
        {
          server = {
            interface = ["0.0.0.0" "::0"];
            tls-system-cert = "yes";
            port = cfg.port;
            access-control = [
              "127.0.0.0/8 allow"
              "::1 allow"
              "192.168.0.0/16 allow"
              "10.0.0.0/8 allow"
              "172.16.0.0/12 allow"
            ];
            private-address = [
              "10.0.0.0/8"
              "172.16.0.0/12"
              "192.168.0.0/16"
              "169.254.0.0/16"
              "fd00::/8"
              "fe80::/10"
            ];

            include = optional (cfg.blocklist != null) cfg.blocklist;

            harden-glue = true;
            harden-dnssec-stripped = true;
            use-caps-for-id = false;
            prefetch = true;
            edns-buffer-size = 1232;

            hide-identity = "yes";
            hide-version = "yes";
          };
          # forward-zone = [
          #   {
          #     name = ".";
          #     forward-addr = [
          #       "9.9.9.9#dns.quad9.net"
          #       "149.112.112.112#dns.quad9.net"
          #     ];
          #     forward-tls-upstream = "yes";
          #   }
          # ];
          remote-control.control-enable = true;
        }
        (mkIf cfg.dns64.enable {
          module-config = "dns64 validator iterator";
          dns64-prefix = cfg.dns64.prefix;
          server.do-nat64 = "yes";
        })
      ];
    };

    # Open firewall ports for DNS
    networking.firewall = {
      allowedUDPPorts = [cfg.port];
      allowedTCPPorts = [cfg.port];
    };
  };
}
