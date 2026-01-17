{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.jellyfin;
in {
  imports = [
    inputs.declarative-jellyfin.nixosModules.default
  ];

  options.cosmos.services.jellyfin = {
    enable = mkEnableOption "jellyfin";
  };

  config = mkIf cfg.enable {
    sops.secrets = {
      "keys/jellyfin/oauth-client-secret" = {
        owner = "kanidm";
        mode = "0640";
      };
    };

    cosmos.system.impermanence.persist.directories = ["/var/lib/jellyfin"];

    users.users = {
      jellyfin = {
        isSystemUser = true;
        group = "jellyfin";
        extraGroups = ["video" "render"];
      };
    };

    users.groups = {
      jellyfin = {};
    };

    services = {
      declarative-jellyfin = {
        enable = true;
        serverId = "67f0071ab42a4aeabc0c7175b9ba3191";

        user = "jellyfin";
        group = "jellyfin";

        encoding = {
          enableVppTonemapping = true;
          enableTonemapping = true;
          tonemappingAlgorithm = "bt2390";
          enableHardwareEncoding = true;
          hardwareAccelerationType = "vaapi";
          enableDecodingColorDepth10Hevc = true;
          allowHevcEncoding = true;
          allowAv1Encoding = true;
          hardwareDecodingCodecs = [
            "h264"
            "hevc"
            "mpeg2video"
            "vc1"
            "vp9"
            "av1"
          ];
        };

        libraries = {
          Movies = {
            enabled = true;
            contentType = "movies";
            pathInfos = ["/tank/media/movies"];
            typeOptions.Movies = {
              metadataFetchers = [
                "The Open Movie Database"
                "TheMovieDb"
              ];
              imageFetchers = [
                "The Open Movie Database"
                "TheMovieDb"
              ];
            };
          };
          Shows = {
            enabled = true;
            contentType = "tvshows";
            pathInfos = ["/tank/media/shows"];
          };
          Books = {
            enabled = true;
            contentType = "books";
            pathInfos = ["/tank/media/books"];
          };
          Music = {
            enabled = true;
            contentType = "music";
            pathInfos = ["/tank/media/music"];
          };
        };

        users = {
          Admin = {
            mutable = false;
            password = "123";
            permissions = {
              isAdministrator = true;
            };
          };
        };

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
              content = {
                Name = "Jellyfin Stable";
                Url = "https://repo.jellyfin.org/files/plugin/manifest.json";
              };
              tag = "RepositoryInfo";
            }
            {
              content = {
                Name = "Jellyfin SSO Plugin";
                Url = "https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json";
              };
              tag = "RepositoryInfo";
            }
            {
              content = {
                Name = "Intro Skipper";
                Url = "https://intro-skipper.org/manifest.json";
              };
              tag = "RepositoryInfo";
            }
          ];
        };

        # apikeys = {
        #   Jellyseerr = {
        #     key = "78878bf9fc654ff78ae332c63de5aeb6";
        #   };
        #   Homarr = {
        #     keyPath = ../tests/example_apikey.txt;
        #   };
        # };
      };

      nginx.virtualHosts = {
        "jellyfin.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";

          locations."/" = {
            proxyPass = "http://127.0.0.1:8096";
          };
        };
      };

      kanidm.provision = {
        groups = {
          jellyfin-users = {
            members = ["lvdar"];
          };
          jellyfin-movies = {
            members = ["lvdar"];
          };
          jellyfin-admin = {
            members = ["lvdar"];
          };
        };
        systems.oauth2 = {
          jellyfin = {
            displayName = "Jellyfin";
            basicSecretFile = config.sops.secrets."keys/jellyfin/oauth-client-secret".path;
            originUrl = "https://jellyfin.lvdar.nl/sso/OID/redirect/kanidm";
            originLanding = "https://jellyfin.lvdar.nl";
            scopeMaps = {
              jellyfin-users = ["openid" "profile" "email"];
            };
            claimMaps = {
              jellyfin_groups = {
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
    };
  };
}
