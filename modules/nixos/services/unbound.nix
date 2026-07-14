{...}: {
  flake-file.inputs = {
    oisd-big-unbound = {
      url = "https://big.oisd.nl/unbound";
      flake = false;
    };
    oisd-nsfw-unbound = {
      url = "https://nsfw.oisd.nl/unbound";
      flake = false;
    };
  };

  flake.modules.nixos.unbound = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.modules) mkIf mkMerge;
    inherit (lib.types) port str nullOr;
    inherit (lib.lists) optional;

    cfg = config.cosmos.services.unbound;
  in {
    options.cosmos.services.unbound = {
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

    config = {
      cosmos.system.impermanence.persist.directories = with config.services.unbound; [
        {
          directory = stateDir;
          inherit user group;
          mode = "0750";
        }
      ];
      services.unbound = {
        enable = true;
        # Unbound owns port 53 here; it is not fronted by dnscrypt-proxy.
        resolveLocalQueries = true;
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
  };
}
