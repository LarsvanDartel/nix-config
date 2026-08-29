# services.jellyfin (jellarr).
{inputs, ...}: {
  flake-file.inputs.jellarr.url = "github:venkyr77/jellarr";

  den.aspects.services.jellyfin.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.lists) optional;
    inherit (lib.types) bool path port;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.jellyfin;
  in {
    imports = [inputs.jellarr.nixosModules.default];

    options.cosmos.services.jellyfin = {
      expose = mkOption {
        type = bool;
        default = false;
      };
      port = mkOption {
        type = port;
        default = 8096;
      };
      openFirewall = mkOption {
        type = bool;
        default = false;
      };

      vaapiDevice = mkOption {
        type = path;
        default = "/dev/dri/renderD128";
        description = ''
          The render node jellyfin transcodes on.

          Jellyfin keeps this in its own encoding.xml, so before jellarr drove
          it the value was whatever the setup wizard guessed — and it guessed a
          renderD12x number, which on a multi-GPU host names a card only by
          probe order. Set this to the `/dev/dri/by-path/pci-<addr>-render`
          symlink on such a host; see the same option on services.transcode.
        '';
      };
    };

    config = {
      sops.secrets = {
        "keys/jellyfin/oauth-client-secret" = {
          owner = "kanidm";
          mode = "0640";
        };
        "keys/jellyfin/api-key" = {};
        "keys/jellyfin/lvdar-password".owner = "jellyfin";
      };

      sops.templates.jellarr-env = {
        content = ''
          JELLARR_API_KEY=${config.sops.placeholder."keys/jellyfin/api-key"}
        '';
        owner = "jellyfin";
      };

      cosmos.system.impermanence.persist.directories = [
        {
          directory = "/var/lib/jellyfin";
          user = "jellyfin";
          group = "jellyfin";
          mode = "0750";
        }
      ];

      services.jellyfin.enable = true;
      users.users.jellyfin.extraGroups = ["video" "render"];
      networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

      services.jellarr = {
        enable = true;
        user = "jellyfin";
        group = "jellyfin";
        environmentFile = config.sops.templates.jellarr-env.path;

        bootstrap = {
          enable = true;
          apiKeyFile = config.sops.secrets."keys/jellyfin/api-key".path;
        };

        config = {
          version = 1;
          base_url = "http://localhost:${toString cfg.port}";

          encoding = {
            enableHardwareEncoding = true;
            hardwareAccelerationType = "vaapi";
            inherit (cfg) vaapiDevice;
            enableDecodingColorDepth10Hevc = true;
            allowHevcEncoding = true;
            allowAv1Encoding = true;
            hardwareDecodingCodecs = ["h264" "hevc" "mpeg2video" "vc1" "vp9" "av1"];
          };

          library.virtualFolders = [
            {
              name = "Movies";
              collectionType = "movies";
              libraryOptions.pathInfos = [{path = "/tank/media/library/movies";}];
            }
            {
              name = "Shows";
              collectionType = "tvshows";
              libraryOptions.pathInfos = [{path = "/tank/media/library/shows";}];
            }
          ];

          users = [
            {
              name = "Admin";
              password = "123";
              policy.isAdministrator = true;
            }
            {
              name = "lvdar@lvdar.nl";
              passwordFile = config.sops.secrets."keys/jellyfin/lvdar-password".path;
              policy.isAdministrator = true;
            }
          ];

          branding = {
            loginDisclaimer = ''
              <form action="https://jellyfin.lvdar.nl/sso/OID/start/kanidm">
                <button class="raised block emby-button button-submit">
                  Sign in with SSO
                </button>
              </form>
            '';
            customCss = ''
              a.raised.emby-button {
                padding: 0.9em 1em;
                color: inherit !important;
              }

              .disclaimerContainer {
                display: block;
              }
            '';
          };

          system = {
            trickplayOptions = {
              enableHwAcceleration = true;
              enableHwEncoding = true;
            };
            pluginRepositories = [
              {
                name = "Jellyfin Stable";
                url = "https://repo.jellyfin.org/files/plugin/manifest.json";
                enabled = true;
              }
              {
                name = "Jellyfin SSO Plugin";
                url = "https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json";
                enabled = true;
              }
              {
                name = "Intro Skipper";
                url = "https://intro-skipper.org/manifest.json";
                enabled = true;
              }
            ];
          };
        };
      };

      # Dropped when the edge terminates TLS: netbird-proxy forwards straight to
      # cfg.port over the mesh, so there is nothing for a local vhost to do.
      services.nginx.virtualHosts = mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
        "jellyfin.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
          locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };

      services.kanidm.provision = {
        groups = {
          jellyfin-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          jellyfin-movies = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          jellyfin-admin.members = ["lvdar"];
        };
        systems.oauth2.jellyfin = {
          displayName = "Jellyfin";
          basicSecretFile = config.sops.secrets."keys/jellyfin/oauth-client-secret".path;
          originUrl = "https://jellyfin.lvdar.nl/sso/OID/redirect/kanidm";
          originLanding = "https://jellyfin.lvdar.nl";
          scopeMaps.jellyfin-users = ["openid" "profile" "email"];
          supplementaryScopeMaps.jellyfin-users = ["jellyfin_groups"];
          claimMaps.jellyfin_groups = {
            joinType = "array";
            valuesByGroup = {
              jellyfin-users = ["jellyfin"];
              jellyfin-admin = ["jellyfin_admin"];
              jellyfin-movies = ["jellyfin_movies"];
            };
          };
        };
      };
    };
  };
}
