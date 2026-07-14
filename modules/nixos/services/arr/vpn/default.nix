{
  inputs,
  config,
  ...
}: let
  inherit (config.flake.modules.nixos) arr;
in {
  flake-file.inputs.vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

  flake.modules.nixos.arr-vpn = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.modules) mkIf;
    inherit (lib.types) nullOr path listOf str port;
    inherit (lib.lists) optional;

    cfg = config.cosmos.services.arr.vpn;
  in {
    imports = [
      arr
      inputs.vpn-confinement.nixosModules.default
    ];

    options.cosmos.services.arr.vpn = {
      name = mkOption {
        type = str;
        default = "wg";
        description = "The name of the wireguard interface and namespace";
      };

      configFile = mkOption {
        type = nullOr path;
        default = null;
        description = "The path to the wireguard configuration file.";
      };

      postUp = mkOption {
        type = str;
        default = "";
        description = "Command to execute after service starts";
      };

      accessibleFrom = mkOption {
        type = listOf str;
        default = [];
        example = ["192.168.2.0/24"];
      };

      vpnTestService = {
        enable = mkEnableOption ''
          the vpn test service. Useful for testing DNS leaks or if the VPN
          port forwarding works correctly.
        '';

        port = mkOption {
          type = nullOr port;
          default = null;
          description = ''
            The port that netcat listens to on the vpn test service. If set to
            `null`, then netcat will not be started.
          '';
        };
      };

      openTcpPorts = mkOption {
        type = listOf port;
        default = [];
      };

      openUdpPorts = mkOption {
        type = listOf port;
        default = [];
      };
    };

    config = {
      assertions = [
        {
          assertion = cfg.configFile != null;
          message = ''
            The arr.vpn feature requires the arr.vpn.configFile option to be set,
            but it was not.
          '';
        }
      ];

      vpnNamespaces.${cfg.name} = {
        enable = true;
        openVPNPorts = optional (cfg.vpnTestService.port != null) {
          port = cfg.vpnTestService.port;
          protocol = "tcp";
        };
        accessibleFrom =
          [
            "192.168.1.0/24"
            "192.168.0.0/24"
            "127.0.0.1"
          ]
          ++ cfg.accessibleFrom;
        wireguardConfigFile = cfg.configFile;
      };

      systemd.services.arr.postStart = cfg.postUp;

      systemd.services.vpn-test-service = mkIf cfg.vpnTestService.enable {
        enable = true;

        vpnConfinement = {
          enable = true;
          vpnNamespace = cfg.name;
        };

        script = let
          vpn-test = pkgs.writeShellApplication {
            name = "vpn-test";

            runtimeInputs = with pkgs; [util-linux unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];

            text =
              ''
                cd "$(mktemp -d)"

                # DNS information
                dig google.com

                # Print resolv.conf
                echo "/etc/resolv.conf contains:"
                cat /etc/resolv.conf

                # Query resolvconf
                echo "resolvconf output:"
                resolvconf -l
                echo ""

                # Get ip
                echo "Getting IP:"
                curl -s ipinfo.io

                echo -ne "DNS leak test:"
                curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
                chmod +x dnsleaktest.sh
                ./dnsleaktest.sh
              ''
              + (
                if cfg.vpnTestService.port != null
                then ''
                  echo "starting netcat on port ${builtins.toString cfg.vpnTestService.port}:"
                  nc -vnlp ${builtins.toString cfg.vpnTestService.port}
                ''
                else ""
              );
          };
        in "${vpn-test}/bin/vpn-test";
      };
    };
  };
}
