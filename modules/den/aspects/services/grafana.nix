# services.grafana — dashboards over the prometheus on this host.
#
# Published with the NetBird identity gate deliberately OFF and its own
# kanidm OIDC client — the opencloud pattern, not the arr one. The gate
# answers a lapsed session with a 302 to the IdP; Grafana is an SPA whose
# XHR cannot follow it and dies with a bare NetworkError — what took traccar
# down until it was ungated (hosts/gaia.nix). Its own OIDC also avoids a
# second login and carries a role, not just yes/no.
#
# Local admin login kept: kanidm runs on this host behind the same edge, so
# OIDC-only would lock the dashboard exactly when you want to look at it.
{den, ...}: {
  den.aspects.services.grafana = {
    includes = with den.aspects.services; [netbird.client prometheus loki];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.grafana;
      prom = config.cosmos.services.prometheus;
      loki = config.cosmos.services.loki;

      # Hand-written, not imported from grafana.com: an id-pulled dashboard
      # is an unreviewable JSON blob pinned to nothing, breaking silently
      # when metric names change. Covers what the alert rules alert on.
      fleetJson = pkgs.writeText "fleet.json" (builtins.toJSON {
        title = "Fleet";
        uid = "fleet";
        timezone = "browser";
        refresh = "1m";
        time = {
          from = "now-24h";
          to = "now";
        };
        panels = let
          panel = id: title: expr: legend: unit: gridPos: {
            inherit id title gridPos;
            type = "timeseries";
            datasource = {
              type = "prometheus";
              uid = "prometheus";
            };
            targets = [
              {
                inherit expr;
                legendFormat = legend;
                refId = "A";
              }
            ];
            fieldConfig = {
              defaults = {
                inherit unit;
                custom.fillOpacity = 8;
              };
              overrides = [];
            };
          };
        in [
          (panel 1 "CPU busy" ''
              100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
            '' "{{instance}}" "percent" {
              h = 8;
              w = 12;
              x = 0;
              y = 0;
            })
          (panel 2 "Memory used" ''
              100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)
            '' "{{instance}}" "percent" {
              h = 8;
              w = 12;
              x = 12;
              y = 0;
            })
          (panel 3 "Filesystem used" ''
              100 - (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"}
                / node_filesystem_size_bytes * 100)
            '' "{{instance}} {{mountpoint}}" "percent" {
              h = 8;
              w = 12;
              x = 0;
              y = 8;
            })
          (panel 4 "Failed units" ''
              sum by (instance) (node_systemd_unit_state{state="failed"})
            '' "{{instance}}" "short" {
              h = 8;
              w = 12;
              x = 12;
              y = 8;
            })
        ];
      });

      dashboardDir = pkgs.runCommand "grafana-dashboards" {} ''
        mkdir -p $out
        cp ${fleetJson} $out/fleet.json
      '';
    in {
      options.cosmos.services.grafana = {
        port = mkOption {
          type = port;
          default = 3000;
          description = ''
            Free here — but note 3003 and 3030 are not, and opencloud holds
            most of 9091-9304, so this host is worth checking before claiming
            a port.
          '';
        };

        domain = mkOption {
          type = str;
          default = "grafana.lvdar.nl";
          description = "Public name. Must match the published service on gaia.";
        };

        authDomain = mkOption {
          type = str;
          default = "auth.lvdar.nl";
          description = "kanidm's public origin.";
        };
      };

      config = {
        sops.secrets = {
          # Read by kanidm to provision the client...
          "keys/grafana/oauth-client-secret".owner = "kanidm";
          # ...and by grafana to authenticate as it. Two entries over one key
          # rather than a shared group, so neither service can read the
          # other's secrets by being in it.
          "grafana/oauth-client-secret" = {
            key = "keys/grafana/oauth-client-secret";
            owner = "grafana";
          };
          # Grafana encrypts datasource credentials in its own database with
          # this, and no longer ships a default. Losing it means those secrets
          # cannot be decrypted, so it is generated once and kept, not derived.
          "keys/grafana/secret-key".owner = "grafana";
          # Grafana ships admin/admin, and this instance is published — the
          # break-glass local login was a login anyone on the internet had
          # until this existed. Caveat: grafana only reads this when it
          # *creates* the admin account; setting it later changes nothing,
          # silently — remove /var/lib/grafana/data/grafana.db (provisioned
          # content comes back from nix) or `grafana cli admin
          # reset-admin-password`.
          "keys/grafana/admin-password".owner = "grafana";
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/grafana";
            user = "grafana";
            group = "grafana";
            mode = "0750";
          }
        ];

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.grafana = {
          enable = true;

          settings = {
            server = {
              http_addr = "0.0.0.0";
              http_port = cfg.port;
              inherit (cfg) domain;
              # Absolute and https: grafana builds its OIDC redirect_uri
              # from this — wrong and kanidm rejects the callback under
              # strict redirect matching (same failure the netbird dashboard
              # hit).
              root_url = "https://${cfg.domain}";
            };

            analytics.reporting_enabled = false;

            security = {
              secret_key = "$__file{${config.sops.secrets."keys/grafana/secret-key".path}}";
              admin_password = "$__file{${config.sops.secrets."keys/grafana/admin-password".path}}";
            };

            "auth.generic_oauth" = {
              enabled = true;
              name = "kanidm";
              icon = "signin";
              client_id = "grafana";
              client_secret = "$__file{${config.sops.secrets."grafana/oauth-client-secret".path}}";
              scopes = "openid profile email";
              auth_url = "https://${cfg.authDomain}/ui/oauth2";
              token_url = "https://${cfg.authDomain}/oauth2/token";
              api_url = "https://${cfg.authDomain}/oauth2/openid/grafana/userinfo";
              use_pkce = true;
              allow_sign_up = true;
              login_attribute_path = "preferred_username";

              # kanidm emits grafana_role from its claim map; no role means
              # Viewer. Admin is not the default — the OIDC group grants it,
              # so revoking in kanidm actually revokes.
              role_attribute_path = "contains(grafana_role[*], 'Admin') && 'Admin' || 'Viewer'";
            };

            # Kept deliberately (see header): OIDC-only would make a Grafana
            # outage and a kanidm outage the same event. Defensible only
            # because the admin password above is a real one — with the
            # shipped default this was an open door.
            auth.disable_login_form = false;
          };

          provision = {
            enable = true;

            datasources.settings.datasources = [
              {
                name = "Prometheus";
                uid = "prometheus";
                type = "prometheus";
                access = "proxy";
                url = "http://127.0.0.1:${toString prom.port}";
                isDefault = true;
              }
              # Without this the logs are collected and stored and simply
              # cannot be read: Explore has nothing to query them with.
              {
                name = "Loki";
                uid = "loki";
                type = "loki";
                access = "proxy";
                url = "http://127.0.0.1:${toString loki.port}";
              }
            ];

            dashboards.settings.providers = [
              {
                name = "fleet";
                # A directory, not the .json itself. Grafana's file provider
                # watches a folder; handed a file it logs "error watching
                # folder" and the dashboard silently never appears.
                options.path = dashboardDir;
                # Provisioned dashboards are read-only in the UI, which is the
                # point: an edit made in the browser would be silently reverted
                # on the next deploy, so better it cannot be made.
                allowUiUpdates = false;
              }
            ];
          };
        };
      };
    };
  };
}
