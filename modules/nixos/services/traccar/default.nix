{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool port listOf enum;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) concatMapStringsSep concatStringsSep toUpper;
  inherit (lib.attrsets) mapAttrsToListRecursive mapAttrsRecursive recursiveUpdate;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.services.traccar;
  stateDirectory = "/var/lib/traccar";
  configFilePath = "${stateDirectory}/config.xml";

  # Map leafs to XML <entry> elements as expected by traccar, using
  # dot-separated keys for nested attribute paths.
  mapLeafs = mapAttrsRecursive (
    path: value: "<entry key='${lib.concatStringsSep "." path}'>${value}</entry>"
  );

  mkConfigEntry = config: lib.collect builtins.isString (mapLeafs config);

  mkConfig = configurationOptions:
    pkgs.writeText "traccar.xml" ''
      <?xml version='1.0' encoding='UTF-8'?>
      <!DOCTYPE properties SYSTEM 'http://java.sun.com/dtd/properties.dtd'>
      <properties>
          ${builtins.concatStringsSep "\n" (mkConfigEntry configurationOptions)}
      </properties>
    '';

  toPlaceHolder = path: "@${concatMapStringsSep "_" (x: toUpper x) path}@";

  addSecretPlaceholders = settings: secrets:
    recursiveUpdate settings (
      mapAttrsRecursive (path: _: toPlaceHolder path)
      secrets
    );

  generateConfig = settings: secrets:
    pkgs.writeShellScriptBin "traccar-generate-config" ''
      set -euo pipefail
      umask 077

      install -d -m 750 -o traccar -g traccar "${stateDirectory}"
      install -m 600 -o traccar -g traccar "${mkConfig (addSecretPlaceholders settings secrets)}" "${configFilePath}"

      # Create the environment file with placeholders
      cp ${mkConfig (addSecretPlaceholders settings secrets)} ${configFilePath}

      # Replace each placeholder with the actual secret
      ${concatStringsSep "\n" (mapAttrsToListRecursive (path: value: ''
          ${pkgs.replace-secret}/bin/replace-secret \
            "${toPlaceHolder path}" \
            "${value}" \
            ${configFilePath}
        '')
        secrets)}
    '';

  protocolPorts = {
    osmand = 5055;
  };

  selectedPorts =
    map (p: protocolPorts.${p}) cfg.protocols;

  settings = {
    protocol = lib.genAttrs cfg.protocols (name: {
      port = toString protocolPorts.${name};
    });
    database = {
      driver = "org.h2.Driver";
      password = "";
      url = "jdbc:h2:${stateDirectory}/traccar";
      user = "sa";
    };
    logger.console = "true";
    web = {
      port = toString cfg.port;
      url = "https://traccar.lvdar.nl";
      override = "${stateDirectory}/override";
    };
    openid = {
      force = "true";
      clientId = "traccar";
      issuerUrl = "https://auth.lvdar.nl/oauth2/openid/traccar";
      groupsClaimName = "traccar_groups";
      allowGroup = "traccar";
      adminGroup = "traccar_admin";
    };
  };

  secrets = {
    openid.clientSecret = config.sops.secrets."keys/traccar/oauth-client-secret".path;
  };
in {
  options.cosmos.services.traccar = {
    enable = mkEnableOption "traccar";

    port = mkOption {
      type = port;
      default = 8082;
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.expose;
    };

    expose = mkOption {
      type = bool;
      default = false;
    };

    protocols = mkOption {
      type = listOf (enum (builtins.attrNames protocolPorts));
      default = [];
      example = ["osmand"];
      description = "Enabled Traccar device protocols";
    };
  };

  config = mkIf cfg.enable {
    users.users.traccar = {
      isSystemUser = true;
      group = "traccar";
    };

    users.groups.traccar = {};
    users.users.kanidm.extraGroups = ["traccar"];

    sops.secrets = {
      "keys/traccar/oauth-client-secret" = {
        owner = "traccar";
        group = "traccar";
        mode = "0640";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port] ++ selectedPorts;
      allowedUDPPorts = selectedPorts;
    };

    systemd.services.traccar = {
      enable = true;
      description = "Traccar";

      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        User = "traccar";
        Group = "traccar";
        WorkingDirectory = "${pkgs.traccar}";
        ExecStartPre = ["${generateConfig settings secrets}/bin/traccar-generate-config"];
        ExecStart = "${getExe pkgs.traccar} ${configFilePath}";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = 10;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        StateDirectory = "traccar";
        SuccessExitStatus = 143;
        Type = "simple";
      };
    };

    services = {
      nginx.virtualHosts = mkIf cfg.expose {
        "traccar.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";

          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
          };
        };
      };

      kanidm.provision = {
        groups = {
          traccar-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          traccar-admin = {
            members = ["lvdar"];
          };
        };
        systems.oauth2 = {
          traccar = {
            displayName = "Traccar";
            basicSecretFile = config.sops.secrets."keys/traccar/oauth-client-secret".path;
            allowInsecureClientDisablePkce = true;
            originUrl = "https://traccar.lvdar.nl/api/session/openid/callback";
            originLanding = "https://traccar.lvdar.nl";
            scopeMaps = {
              traccar-users = ["openid" "profile" "email" "traccar_groups"];
            };
            claimMaps = {
              traccar_groups = {
                joinType = "array";
                valuesByGroup = {
                  traccar-users = ["traccar"];
                  traccar-admin = ["traccar_admin"];
                };
              };
            };
          };
        };
      };
    };
  };
}
