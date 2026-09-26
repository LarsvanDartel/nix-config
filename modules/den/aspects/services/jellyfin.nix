# services.jellyfin (jellarr).
{inputs, ...}: {
  flake-file.inputs.jellarr.url = "github:venkyr77/jellarr";

  # jellarr pins pnpmDeps.hash against pnpm 11.15.0 (its own locked
  # nixpkgs); our shared pkgs is newer and ships pnpm 12.x, whose store
  # format changes the fixed-output hash for the same pnpm-lock.yaml,
  # breaking every nixpkgs bump. Patch the one stale hash instead of
  # forking the whole nixosModule; drop once upstream regenerates it
  # against a current nixpkgs.
  nixpkgs.overlays = [
    (final: prev: {
      fetchPnpmDeps = args:
        prev.fetchPnpmDeps (
          if
            args.pname or null
            == "jellarr"
            && args.hash == "sha256-jo1BjRAjjfNKF0xb5cLCuELSveHeJ98iLPhMDKP1QbI="
          then args // {hash = "sha256-qNVnhHjTFPhJxJ8oZPBSfJs2OjNSlbmS31okZuSGWMU=";}
          else args
        );
    })
  ];

  den.aspects.services.jellyfin.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.lists) optional;
    inherit (lib.types) bool path port;
    inherit (lib.modules) mkIf mkForce;

    cfg = config.cosmos.services.jellyfin;

    # jellarr's client only ever sends the legacy X-Emby-Token header, but
    # our Jellyfin has EnableLegacyAuthorization=false (upstream's current
    # default), so that header is never even read and every request
    # 401s. jellarr's own HTTP wrapper doesn't treat that as an error
    # (openapi-fetch never populates `error` for a body-less 401), so it
    # silently feeds `undefined` in as the "current" server state — which
    # is what actually throws ("Cannot set properties of undefined
    # (setting '$root')") once the encoding-diff step tries to compute a
    # patch against it. Confirmed live against endeavour's Jellyfin:
    # sending both headers, i.e. adding the modern `Authorization`
    # header Jellyfin reads unconditionally, fixes auth and jellarr
    # applies cleanly. Patch the one line in the built bundle rather than
    # fork the module; drop once jellarr grows a non-legacy client.
    jellarrPkg = pkgs.callPackage "${inputs.jellarr}/nix/package.nix" {};
    jellarrPatched = jellarrPkg.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          substituteInPlace $out/share/bundle.cjs --replace-fail \
            "headers.set(\"X-Emby-Token\", apiKey);" \
            "headers.set(\"X-Emby-Token\", apiKey);
                headers.set(\"Authorization\", 'MediaBrowser Client=\"jellarr\", Device=\"cli\", DeviceId=\"jellarr\", Version=\"0.1.0\", Token=\"' + apiKey + '\"');"
        '';
    });
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
            {
              # No movie/show metadata to scrape here, so "homevideos" — plain
              # video files, no online identification.
              name = "Lectures";
              collectionType = "homevideos";
              libraryOptions.pathInfos = [{path = "/tank/media/library/lectures";}];
            }
            {
              name = "Anime";
              collectionType = "tvshows";
              libraryOptions.pathInfos = [{path = "/tank/media/library/anime";}];
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

      # jellarr's own build always resolves the systemd unit's ExecStart
      # to `pkgs.callPackage ../package.nix {}` internally (no package
      # option to override); mkForce it to the auth-patched build above.
      systemd.services.jellarr.serviceConfig.ExecStart = mkForce (lib.getExe jellarrPatched);

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
