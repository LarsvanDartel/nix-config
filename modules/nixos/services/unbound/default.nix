{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) port listOf str;
  inherit (lib.lists) optional;
  inherit (lib.meta) getExe getExe';
  inherit (lib.strings) concatMapStringsSep;

  cfg = config.cosmos.services.unbound;
in {
  options.cosmos.services.unbound = {
    enable = mkEnableOption "unbound";
    port = mkOption {
      type = port;
      default = 53;
      description = "Port for Unbound DNS service";
    };
    blocklists = mkOption {
      type = listOf str;
      default = [];
      description = "List of blocklist URLs to use for DNS blocking";
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

            include = optional (cfg.blocklists != []) "/var/lib/unbound/blocklists/blocked-domains.conf";

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

    # Blocklist configuration
    systemd.services.unbound-blocklist = mkIf (cfg.blocklists != []) {
      description = "Download and update DNS blocklists";
      wantedBy = ["multi-user.target"];
      requires = ["unbound.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail

        BLOCKLIST_DIR="/var/lib/unbound/blocklists"
        OUTPUT_FILE="$BLOCKLIST_DIR/blocked-domains.conf"
        TEMP_FILE="$BLOCKLIST_DIR/blocked-domains-temp.conf"

        mkdir -p "$BLOCKLIST_DIR"
        touch "$OUTPUT_FILE"

        process_blocklist() {
          url="$1"
          echo "Processing blocklist: $url"

          ${getExe pkgs.curlMinimal} -s -L "$url" >> "$TEMP_FILE"
          echo "" >> "$TEMP_FILE"
        }

        : > "$TEMP_FILE"
        ${concatMapStringsSep "\n" (x: "process_blocklist ${x}") cfg.blocklists}

        ${getExe pkgs.gawk} '!x[$0]++' "$TEMP_FILE" > "$OUTPUT_FILE"
        echo "Blocklist updated successfully"

        if systemctl is-active --quiet unbound.service; then
          echo "Reloading unbound to apply new blocklist"
          ${getExe' pkgs.unbound "unbound-control"} reload
        else
          echo "Unbound is not running, skipping reload"
        fi
      '';
    };

    systemd.timers.unbound-blocklist = mkIf (cfg.blocklists != []) {
      description = "Update DNS blocklists daily";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        AccuracySec = "1h";
        Persistent = true;
      };
    };
  };
}
