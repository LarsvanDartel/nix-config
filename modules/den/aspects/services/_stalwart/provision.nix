# services.stalwart.provision — vendored from nixpkgs PR #552103 (see
# ./default.nix). Changed: meta dropped; `scope` defaults to null (upstream
# throws when it is unset); `secretFiles` added; the readiness loop sleeps
# between attempts (upstream spins) and the script fails on any error.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.stalwart.provision;
  stalwart = config.services.stalwart;
in {
  options.services.stalwart.provision = {
    enable = lib.mkEnableOption "Stalwart Configuration Provisioning";
    enterprise = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow enterprise-only settings";
    };
    package = lib.mkPackageOption pkgs "stalwart-cli" {};
    reloadSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tell Stalwart to reload its settings when complete";
    };
    urls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "The URLs of the Stalwart instance to provision onto. If multiple URLs are specified, they will be cycled through until one succeeds.";
    };
    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = ''
        Files whose contents replace `@@<name>@@` in the plan at runtime, for values the
        schema types as plain strings (secret fields take `"@type" = "File"` instead).
        The splice is textual: contents must not need JSON escaping.
      '';
    };
    timeout = lib.mkOption {
      type = lib.types.nullOr lib.types.numbers.positive;
      default = null;
      example = 300;
      description = "Timeout after this many seconds.";
    };

    singletons = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.json;
      description = "Singletons to configure.";
      example = {
        SystemSettings = {
          defaultHostname = "mail.example.com";
          defaultDomainId = "#mainDomain";
        };
      };
    };
    objects = lib.mkOption {
      type = lib.types.lazyAttrsOf (
        lib.types.submodule {
          options = {
            reconcile = lib.mkOption {
              type = lib.types.bool;
              description = ''
                Whether to use the `reconcile` operation instead of `upsert`, deleting objects in this set that are not explicitly defined.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#reconciling-to-exact-state) for more information.
              '';
              default = false;
            };

            match = lib.mkOption {
              type = lib.types.nullOr (lib.types.either (lib.types.listOf lib.types.str) lib.types.str);
              description = ''
                The fields to match on, a wildcard (`"*"`), or null.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#upsert) for more information.
              '';
              example = ["name"];
              default = null;
            };

            scope = lib.mkOption {
              type = lib.types.nullOr lib.types.json;
              default = null;
              description = ''
                Optional scope to restrict which objects this operation can affect.
                Should be a partial value of the object type.
                This is especially useful when `reconcile` is `true`, only objects that match the scope will be considered for deletion.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#scoping-an-operation-with-scope) for more information.
              '';
            };

            objects = lib.mkOption {
              type = lib.types.lazyAttrsOf lib.types.json;
              description = "The objects in the set. Attribute names define IDs that can be referenced with `#name` elsewhere where an ID is expected.";
            };
          };
        }
      );
      description = "Objects to configure.";
      example = {
        NetworkListener = {
          reconcile = false;
          match = ["name"];
          objects = {
            nl-mgmt = {
              name = "management";
              protocol = "http";
              bind = ["[::]:8080"];
            };
            nl-inc = {
              name = "incoming";
              protocol = "submissions";
              bind = ["[::]:465"];
              implicitTls = true;
            };
          };
        };
        Domain = {
          reconcile = true;
          match = ["name"];
          objects = {
            mainDomain = {
              name = "mail.example.com";
              certificateManagement."@type" = "Manual";
              dkimManagement."@type" = "Manual";
              dnsManagement."@type" = "Manual";
              subAddressing."@type" = "Enabled";
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    let
      variant = type: value: {"@type" = type;} // value;

      plans =
        lib.mapAttrsToList (
          name: value:
            variant "update" {
              object = name;
              value = value;
            }
        )
        cfg.singletons
        ++ lib.mapAttrsToList (
          name: value:
            variant (
              if value.reconcile
              then "reconcile"
              else "upsert"
            ) {
              object = name;
              matchOn = value.match;
              scope = value.scope;
              value = value.objects;
            }
        )
        cfg.objects;

      unsorted = lib.concatMapStringsSep "\n" builtins.toJSON plans;

      sorted =
        pkgs.runCommand "stalwart-provision.ndjson"
        {
          nativeBuildInputs = with pkgs.lua52Packages; [
            lua
            dkjson
          ];
        }
        ''
          gzip -d ${stalwart.package.src}/resources/schema/${
            if lib.versionAtLeast stalwart.package.version "1" && !cfg.enterprise
            then "schema_oss"
            else "schema"
          }.json.gz -c > ./schema.json
          lua ${./provision-check-sort.lua} ${lib.escapeShellArg unsorted} $out ./schema.json ${lib.optionalString cfg.reloadSettings "--reload"}
        '';
    in {
      assertions = [
        {
          assertion = stalwart.enable;
          message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.enable</option> to be true";
        }
        {
          assertion = stalwart.admin.enable;
          message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.admin.enable</option> to be true";
        }
        {
          assertion = lib.versionAtLeast stalwart.package.version "0.16";
          message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.package</option> to be at least version 0.16";
        }
      ];

      systemd.services.stalwart-provision = {
        description = "Stalwart Configuration Provisioning";
        wantedBy = ["multi-user.target"];
        partOf = ["stalwart.service"];
        after = ["stalwart.service"];
        bindsTo = ["stalwart.service"];
        serviceConfig = {
          Type = "oneshot";
          LoadCredential =
            config.systemd.services.stalwart.serviceConfig.LoadCredential
            ++ lib.mapAttrsToList (name: path: "secret-${name}:${path}") cfg.secretFiles;
          RuntimeDirectory = "stalwart-provision";

          ExecStart = pkgs.writeShellScript "stalwart-provision" ''
            set -euo pipefail
            plan="$RUNTIME_DIRECTORY/plan.ndjson"
            install -m 600 ${sorted} "$plan"
            ${lib.concatLines (
              lib.mapAttrsToList (
                name: _: "${lib.getExe pkgs.replace-secret} ${lib.escapeShellArg "@@${name}@@"} \"$CREDENTIALS_DIRECTORY/secret-${name}\" \"$plan\""
              )
              cfg.secretFiles
            )}
            while :; do
              for url in ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.urls}; do
                if ${pkgs.curl}/bin/curl --fail "$url" &>/dev/null; then
                  echo "connection to $url succeeded, attempting to provision onto it"
                  STALWART_URL=$url STALWART_PASSWORD="$(systemd-creds cat ${lib.escapeShellArg stalwart.admin.username})" ${lib.getExe cfg.package} apply --file "$plan"
                  exit
                fi
              done
              sleep 0.25
            done
          '';
          Environment = [
            "STALWART_USER=${lib.escapeShellArg stalwart.admin.username}"
          ];
        };
      };
    }
  );
}
