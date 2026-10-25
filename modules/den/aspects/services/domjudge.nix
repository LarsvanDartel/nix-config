# services.domjudge — DOMjudge programming-contest judge at judge.lvdar.nl,
# preloaded with recent CHipCie contests as open practice contests.
#
# No native OIDC: oauth2-proxy + nginx auth_request set Remote-User, and the
# container's Symfony remote_user authenticator trusts it. Anything that can
# reach 127.0.0.1:8093 or the podman network can therefore claim any user.
#
# The image digests are the PHP2Shell fix: this domserver build carries
# php8.3-fpm 8.3.6-0ubuntu0.24.04.13; earlier builds of the 9.0.1 tag are
# vulnerable. Bump domserver and judgehost together.
{
  den,
  inputs,
  ...
}: let
  domain = "judge.lvdar.nl";

  # Option default and netbird-service target (see services/netbird.nix).
  defaultPort = 8092;
  containerPort = 8093;
  # firefly's oauth2-proxy holds 4181.
  oauthPort = 4182;
in {
  den.aspects.services.domjudge = {
    includes = with den.aspects.services; [nginx netbird.client];

    # Authenticates via oauth2-proxy + kanidm.
    netbird-service = {host, ...}: {
      judge = {
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultPort;
          }
        ];
      };
    };

    kanidm-provision = {
      groups.domjudge-users = {
        overwriteMembers = false;
        members = ["lvdar"];
      };

      oauth2.domjudge = {
        displayName = "DOMjudge";
        basicSecret = "keys/domjudge/oauth-client-secret";
        originUrl = "https://${domain}/oauth2/callback";
        originLanding = "https://${domain}";
        scopeMaps.domjudge-users = ["openid" "profile" "email"];
        # preferred_username is the DOMjudge username: `lvdar`, not the SPN.
        preferShortUsername = true;
      };
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port;

      cfg = config.cosmos.services.domjudge;
      secret = name: config.sops.placeholder."keys/domjudge/${name}";

      containerUnits = map (n: "podman-domjudge-${n}.service") ["mariadb" "domserver" "judgehost"];

      mariadbImage = pkgs.dockerTools.pullImage {
        imageName = "mariadb";
        imageDigest = "sha256:250e1609e93c0e6aecf64bfbab2d84d5e89d2481540fe77447ff6c855c3b1873";
        hash = "sha256-ehHjEvt39nU+9Hk5hfhQvGzDSPU65a56ityTcnTLN7E=";
        finalImageName = "docker.io/library/mariadb";
        finalImageTag = "11.4";
        os = "linux";
        arch = "amd64";
      };
      domserverImage = pkgs.dockerTools.pullImage {
        imageName = "domjudge/domserver";
        imageDigest = "sha256:ae720873114e8abe09c1d81473c0ed4a287b74f1f9fceaa9be087baaeae309f4";
        hash = "sha256-2yT5HjlK3qQ9XwOvfGpel3aVW+IahSnhndFtsb+IfJI=";
        finalImageName = "docker.io/domjudge/domserver";
        finalImageTag = "9.0.1";
        os = "linux";
        arch = "amd64";
      };
      judgehostImage = pkgs.dockerTools.pullImage {
        imageName = "domjudge/judgehost";
        imageDigest = "sha256:61c7361055fcb6b83cfaba276952ad9400dc12933d3b633595ef7edb5391e9c6";
        hash = "sha256-cc+q6pYjUsllcputXaY6ZZDn+Cnzx/HAjc468O3HFvo=";
        finalImageName = "docker.io/domjudge/judgehost";
        finalImageTag = "9.0.1";
        os = "linux";
        arch = "amd64";
      };

      # Own ids and names: the archives' contest.yaml ids (prelims, main,
      # problems) repeat every year, so that file is never uploaded.
      contests =
        map (c: {
          id = "${c.series}${toString c.year}";
          name = "${lib.toUpper c.series} ${toString c.year}";
          url = "https://chipcie.wisv.ch/archive/${toString c.year}/${c.series}/solutions.zip";
        }) [
          {
            series = "dapc";
            year = 2026;
          }
          {
            series = "dapc";
            year = 2025;
          }
          {
            series = "dapc";
            year = 2024;
          }
          {
            series = "bapc";
            year = 2025;
          }
          {
            series = "bapc";
            year = 2024;
          }
          {
            series = "bapc";
            year = 2023;
          }
          {
            series = "nwerc";
            year = 2025;
          }
          {
            series = "nwerc";
            year = 2024;
          }
          {
            series = "nwerc";
            year = 2023;
          }
        ];
      contestsJson = pkgs.writeText "domjudge-contests.json" (builtins.toJSON contests);

      # Type admin: admin + team roles and a team in the hidden Jury category.
      # Other kanidm users are added in the jury UI, username = kanidm short name.
      accountsJson = pkgs.writeText "domjudge-accounts.json" (builtins.toJSON [
        {
          id = "lvdar";
          username = "lvdar";
          name = "lvdar";
          type = "admin";
        }
      ]);

      # The image's judge chroot has gcc, OpenJDK 21 and pypy3 3.9. Newer
      # languages come from this closure, copied into one tree mounted at the
      # chroot's /nix, so submissions see it and not the host store.
      python = pkgs.python3;
      go = pkgs.go;
      node = pkgs.nodejs-slim;
      # Official distributions where nixpkgs' build drags in a toolchain the
      # chroot already has: pkgs.kotlin wraps a 600 MiB OpenJDK and pkgs.rustc
      # a 1.6 GiB LLVM + cc closure. These run on the chroot's java and cc.
      kotlinc = pkgs.runCommand "kotlinc-${pkgs.kotlin.version}" {nativeBuildInputs = [pkgs.unzip];} ''
        unzip -q ${pkgs.kotlin.src}
        mv kotlinc $out
      '';
      # Pinned: bump the version and both hashes together
      # (nix store prefetch-file <url>).
      rustVersion = "1.99.0";
      rustComponent = name: hash:
        pkgs.fetchurl {
          url = "https://static.rust-lang.org/dist/${name}-${rustVersion}-x86_64-unknown-linux-gnu.tar.xz";
          inherit hash;
        };
      rust = pkgs.runCommand "rust-${rustVersion}" {} ''
        tar -xJf ${rustComponent "rustc" "sha256-dxcboqA0X98qvE/t2lXW3geNrnpoUnwovox33MlgS9U="}
        tar -xJf ${rustComponent "rust-std" "sha256-Pljf8tC3IZa16k6QU24XTUAN6IVkpSaUaGuB4JEWmTM="}
        mkdir $out
        cp -r rustc-*/rustc/. rust-std-*/rust-std-x86_64-unknown-linux-gnu/. $out/
      '';
      chrootStore = pkgs.runCommand "domjudge-chroot-store" {} ''
        mkdir -p $out/store
        cp -a --reflink=auto $(<${pkgs.closureInfo {rootPaths = [python kotlinc rust go node];}}/store-paths) $out/store/
      '';

      # Compile scripts; domjudge-import uploads them when the DB's differ.
      mkExecutable = name: substitutions:
        pkgs.runCommand "domjudge-executable-${name}.zip" {nativeBuildInputs = [pkgs.zip];} ''
          cp -r ${./_domjudge/executables + "/${name}"} src
          chmod -R u+w src
          substituteInPlace src/run ${substitutions}
          cd src
          find . -exec touch -h -d @315532800 {} +
          find . -type f | sort | zip -q -X -@ $out
        '';
      executables = {
        py3 = mkExecutable "py3" "--replace-fail @python3@ ${python}/bin/python3";
        kt = mkExecutable "kt" "--replace-fail @kotlinc@ ${kotlinc}";
        rs = mkExecutable "rs" "--replace-fail @rust@ ${rust}";
        go = mkExecutable "go" "--replace-fail @go@ ${go}";
        js = mkExecutable "js" "--replace-fail @node@ ${node}/bin/node";
      };

      # Exactly these languages are enabled: POST /languages disables the rest.
      languagesJson = pkgs.writeText "domjudge-languages.json" (builtins.toJSON [
        {id = "c";}
        {id = "cpp";}
        {id = "java";}
        {
          id = "kotlin";
          name = "Kotlin ${lib.versions.majorMinor pkgs.kotlin.version}";
          # kt/run detects the main class, as Java's script does.
          entry_point_required = false;
          compiler.version_command = "${kotlinc}/bin/kotlinc -version";
          runner.version_command = "${kotlinc}/bin/kotlin -version";
        }
        {
          id = "python3";
          name = "Python ${lib.versions.majorMinor python.version}";
          extensions = ["py" "py3"];
          compiler.version_command = "${python}/bin/python3 --version";
          runner.version_command = "${python}/bin/python3 --version";
        }
        {
          id = "rust";
          name = "Rust ${lib.versions.majorMinor rustVersion}";
          compiler.version_command = "${rust}/bin/rustc --version";
        }
        {
          id = "go";
          name = "Go ${lib.versions.majorMinor go.version}";
          extensions = ["go"];
          compiler.version_command = "${go}/bin/go version";
        }
        {
          id = "javascript";
          name = "JavaScript (Node.js ${lib.versions.major node.version})";
          runner.version_command = "${node}/bin/node --version";
        }
      ]);

      waitApi = pkgs.writeShellApplication {
        name = "domjudge-wait-api";
        runtimeInputs = with pkgs; [coreutils curl];
        text = ''
          # First start installs/migrates the DB before nginx comes up.
          for _ in $(seq 120); do
            [ "$(curl -s -o /dev/null -w '%{http_code}' ${api}/info || true)" = 200 ] && exit 0
            sleep 5
          done
          echo "domserver API not up after 10 minutes" >&2
          exit 1
        '';
      };

      # SQL for what the API cannot do; runs as root (ExecStartPre=+).
      seed = pkgs.writeShellApplication {
        name = "domjudge-seed";
        runtimeInputs = [config.virtualisation.podman.package];
        text = ''
          # shellcheck disable=SC2016 # expanded inside the container
          podman exec -i domjudge-mariadb sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" domjudge' <<'SQL'
          -- The install loads DOMjudge's example data.
          DELETE FROM contest WHERE externalid = 'demo';
          DELETE FROM problem WHERE externalid IN ('hello', 'fltcmp', 'boolfind');
          DELETE FROM executable WHERE execid = 'boolfind_cmp';
          DELETE FROM user WHERE username = 'demo';
          DELETE FROM team WHERE externalid = 'exteam';
          DELETE FROM team_affiliation WHERE externalid = 'utrecht';
          DELETE FROM judgehost WHERE hostname = 'example-judgehost1';
          -- No default Go language, and POST /languages skips unknown ones.
          INSERT IGNORE INTO executable (execid, description, type) VALUES ('go', 'go', 'compile');
          INSERT IGNORE INTO language (langid, externalid, name, extensions, allow_submit, compile_script)
            VALUES ('go', 'go', 'Go', '["go"]', 0, 'go');
          SQL
        '';
      };

      api = "http://127.0.0.1:${toString containerPort}/api/v4";

      # Its own executable so `set -e` holds per contest: inside a function
      # used with `||`, errexit is ignored.
      importContest = pkgs.writeShellApplication {
        name = "domjudge-import-contest";
        runtimeInputs = with pkgs; [coreutils curl jq unzip yq-go];
        text = ''
          id=$1 name=$2 url=$3
          api=${api}
          curlrc="$CACHE_DIRECTORY/curlrc"
          dj() { curl -sS --fail-with-body -K "$curlrc" "$@"; }

          created=false
          if [ "$(curl -sS -o /dev/null -w '%{http_code}' -K "$curlrc" "$api/contests/$id")" = 200 ]; then
            if dj "$api/contests/$id/problems" | jq -e 'length > 0 and all(.[]; .test_data_count > 0)' >/dev/null; then
              echo "$id: already imported"
              exit 0
            fi
          else
            created=true
          fi

          dir="$CACHE_DIRECTORY/$id"
          rm -rf "$dir"
          mkdir -p "$dir"
          trap 'rm -rf "$dir"' EXIT
          echo "$id: downloading $url"
          curl -sSfL --retry 3 -o "$dir/archive.zip" "$url"
          unzip -q "$dir/archive.zip" -d "$dir/x" -x samples.zip
          rm "$dir/archive.zip"

          if $created; then
            jq -n --arg id "$id" --arg name "$name" --arg start "$(date --iso-8601=seconds)" \
              '{id: $id, name: $name, formal_name: $name, start_time: $start, duration: "87600:00:00"}' >"$dir/contest.json"
            dj -F "json=@$dir/contest.json;type=application/json" "$api/contests" >/dev/null
            dj -F "problemset=@$dir/x/contest.pdf;type=application/pdf" "$api/contests/$id/problemset" >/dev/null
            # add-data is not idempotent (it always inserts), so it only ever runs here.
            if ! dj -F "data=@$dir/x/problems.yaml" "$api/contests/$id/problems/add-data" >/dev/null; then
              echo "$id: adding problems failed; delete contest $id in the jury UI, then restart domjudge-import" >&2
              exit 1
            fi
          fi

          for problem in $(yq -r '.[].id' "$dir/x/problems.yaml"); do
            if dj "$api/contests/$id/problems/$problem" | jq -e '.test_data_count > 0' >/dev/null; then
              continue
            fi
            echo "$id: importing $problem"
            dj -F "zip=@$dir/x/$problem.zip;type=application/zip" -F "problem=$problem" \
              "$api/contests/$id/problems" | jq -c '{problem_id, danger: .messages.danger}'
          done
        '';
      };

      importAll = pkgs.writeShellApplication {
        name = "domjudge-import";
        runtimeInputs = with pkgs; [coreutils curl findutils jq unzip importContest];
        text = ''
          api=${api}
          umask 077
          printf 'user = "admin:%s"\n' "$(<"$CREDENTIALS_DIRECTORY/admin-password")" >"$CACHE_DIRECTORY/curlrc"
          dj() { curl -sS --fail-with-body -K "$CACHE_DIRECTORY/curlrc" "$@"; }

          # What DOMjudge judges with: file contents and executable bits.
          digest() {
            local d
            d=$(mktemp -d -p "$CACHE_DIRECTORY")
            unzip -q "$1" -d "$d" 2>/dev/null || true
            (cd "$d" && find . -type f -print0 | sort -z | xargs -0 sha256sum && find . -type f -perm -u+x | sort)
            rm -rf "$d"
          }
          for e in ${lib.concatStringsSep " " (lib.mapAttrsToList (id: zip: "${id}=${zip}") executables)}; do
            id=''${e%%=*} zip=''${e#*=}
            # A new language's executable has no files yet.
            if ! dj "$api/executables/$id" | jq -r . | base64 -d >"$CACHE_DIRECTORY/current.zip"; then
              : >"$CACHE_DIRECTORY/current.zip"
            fi
            if [ "$(digest "$zip")" != "$(digest "$CACHE_DIRECTORY/current.zip")" ]; then
              echo "updating executable $id"
              dj -F "executable=@$zip;type=application/zip" "$api/languages/$id/executable"
            fi
          done
          dj -F "json=@${languagesJson};type=application/json" "$api/languages" >/dev/null

          dj -F "json=@${accountsJson};type=application/json" "$api/users/accounts"
          echo

          failed=()
          while read -r c; do
            id=$(jq -r .id <<<"$c")
            domjudge-import-contest "$id" "$(jq -r .name <<<"$c")" "$(jq -r .url <<<"$c")" || failed+=("$id")
          done < <(jq -c '.[]' ${contestsJson})
          if [ "''${#failed[@]}" -gt 0 ]; then
            echo "failed: ''${failed[*]}" >&2
            exit 1
          fi
        '';
      };
    in {
      options.cosmos.services.domjudge.port = mkOption {
        type = port;
        default = defaultPort;
      };

      config = {
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        virtualisation.podman.enable = true;
        virtualisation.oci-containers.backend = "podman";

        # podman's bridge/veths are statically addressed.
        networking.dhcpcd.denyInterfaces = ["dj-br0" "veth*"];

        # The mariadb entrypoint chowns its own datadir: tmpfiles must not.
        systemd.tmpfiles.rules = [
          "d /tank/domjudge 0700 root root -"
          "d /tank/domjudge/mariadb - - - -"
        ];

        sops = {
          secrets = {
            "keys/domjudge/admin-password" = {};
            "keys/domjudge/judgehost-password" = {};
            "keys/domjudge/db-password" = {};
            "keys/domjudge/db-root-password" = {};
            "keys/domjudge/cookie-secret" = {};
            # Shared with kanidm's host (services/kanidm.nix), hence hosts/common.
            "keys/domjudge/oauth-client-secret".sopsFile =
              builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
          };

          templates = {
            "domjudge-mariadb.env".content = ''
              MARIADB_ROOT_PASSWORD=${secret "db-root-password"}
              MARIADB_PASSWORD=${secret "db-password"}
            '';
            "domjudge-domserver.env".content = ''
              MYSQL_ROOT_PASSWORD=${secret "db-root-password"}
              MYSQL_PASSWORD=${secret "db-password"}
              DJ_ADMIN_PASSWORD=${secret "admin-password"}
              DJ_JUDGEHOST_PASSWORD=${secret "judgehost-password"}
            '';
            "domjudge-judgehost.env".content = ''
              JUDGEDAEMON_PASSWORD=${secret "judgehost-password"}
            '';
          };
        };

        virtualisation.oci-containers.containers = {
          domjudge-mariadb = {
            image = "docker.io/library/mariadb:11.4";
            imageFile = mariadbImage;
            pull = "never";
            networks = ["domjudge"];
            extraOptions = ["--ip=10.89.42.2"];
            environment = {
              MARIADB_DATABASE = "domjudge";
              MARIADB_USER = "domjudge";
            };
            environmentFiles = [config.sops.templates."domjudge-mariadb.env".path];
            volumes = ["/tank/domjudge/mariadb:/var/lib/mysql"];
            # Upstream's compose flags; the packet size is for large testcases.
            cmd = ["--max-connections=1000" "--max-allowed-packet=512M"];
          };

          domjudge-domserver = {
            image = "docker.io/domjudge/domserver:9.0.1";
            imageFile = domserverImage;
            pull = "never";
            dependsOn = ["domjudge-mariadb"];
            networks = ["domjudge"];
            extraOptions = ["--ip=10.89.42.3"];
            ports = ["127.0.0.1:${toString containerPort}:80"];
            environment = {
              MYSQL_HOST = "10.89.42.2";
              MYSQL_USER = "domjudge";
              MYSQL_DATABASE = "domjudge";
            };
            environmentFiles = [config.sops.templates."domjudge-domserver.env".path];
            volumes = ["${./_domjudge/start.ro}:/scripts/start.ro:ro"];
          };

          # Privileged + the host cgroup tree is upstream's documented judgehost
          # setup. runguard unshares the network namespace, so submissions
          # cannot reach the domserver.
          domjudge-judgehost = {
            image = "docker.io/domjudge/judgehost:9.0.1";
            imageFile = judgehostImage;
            pull = "never";
            dependsOn = ["domjudge-domserver"];
            hostname = "judgehost";
            privileged = true;
            networks = ["domjudge"];
            extraOptions = ["--ip=10.89.42.4" "--cgroupns=host"];
            # judgehost-start adds the toolchain mount to every judging's chroot.
            cmd = ["/scripts/judgehost-start.sh"];
            volumes = [
              "/sys/fs/cgroup:/sys/fs/cgroup"
              "${./_domjudge/judgehost-start.sh}:/scripts/judgehost-start.sh:ro"
              "${chrootStore}:/chroot/domjudge/nix:ro"
            ];
            environment = {
              DOMSERVER_BASEURL = "http://10.89.42.3/";
              JUDGEDAEMON_USERNAME = "judgehost";
              DAEMON_ID = "0";
            };
            environmentFiles = [config.sops.templates."domjudge-judgehost.env".path];
          };
        };

        systemd.services = lib.mkMerge [
          # The domserver exits if the DB is not up within 90 s, the judgehost
          # if the API is not up yet.
          (lib.genAttrs (map (lib.removeSuffix ".service") containerUnits) (_: {
            serviceConfig.RestartSec = "10s";
            unitConfig = {
              StartLimitIntervalSec = "15min";
              StartLimitBurst = 60;
            };
          }))
          {
            podman-domjudge-mariadb.unitConfig.RequiresMountsFor = ["/tank/domjudge"];

            # Static IPs, no DNS: independent of aardvark-dns and the firewall's 53.
            podman-network-domjudge = {
              path = [config.virtualisation.podman.package];
              before = containerUnits;
              requiredBy = containerUnits;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                podman network exists domjudge || podman network create --subnet=10.89.42.0/24 --gateway=10.89.42.1 --interface-name=dj-br0 --disable-dns domjudge
              '';
            };

            # See firefly.nix: hand-rolled, services.oauth2-proxy is a singleton.
            oauth2-proxy-domjudge = {
              description = "oauth2-proxy for DOMjudge";
              after = ["network.target" "kanidm.service"];
              wantedBy = ["multi-user.target"];
              serviceConfig = {
                DynamicUser = true;
                LoadCredential = [
                  "client-secret:${config.sops.secrets."keys/domjudge/oauth-client-secret".path}"
                  "cookie-secret:${config.sops.secrets."keys/domjudge/cookie-secret".path}"
                ];
                ExecStart = ''
                  ${lib.getExe pkgs.oauth2-proxy} \
                    --http-address=127.0.0.1:${toString oauthPort} \
                    --provider=oidc \
                    --oidc-issuer-url=https://auth.lvdar.nl/oauth2/openid/domjudge \
                    --client-id=domjudge \
                    --client-secret-file=%d/client-secret \
                    --cookie-secret-file=%d/cookie-secret \
                    --redirect-url=https://${domain}/oauth2/callback \
                    --upstream=static://202 \
                    --email-domain=* \
                    --whitelist-domain=${domain} \
                    --set-xauthrequest \
                    --reverse-proxy \
                    --trusted-proxy-ip=127.0.0.1/32 \
                    --trusted-proxy-ip=::1/128 \
                    --code-challenge-method=S256 \
                    --skip-provider-button
                '';
                Restart = "on-failure";
                RestartSec = "10s";
              };
              unitConfig = {
                StartLimitIntervalSec = "15min";
                StartLimitBurst = 60;
              };
            };

            domjudge-import = {
              description = "Import CHipCie contests into DOMjudge";
              wantedBy = ["multi-user.target"];
              requires = ["podman-domjudge-domserver.service"];
              wants = ["network-online.target"];
              after = ["podman-domjudge-domserver.service" "network-online.target"];
              serviceConfig = {
                # RemainAfterExit: a changed contest list restarts it on switch.
                Type = "oneshot";
                RemainAfterExit = true;
                DynamicUser = true;
                # Up to ~0.9 GB per contest on the unpersisted root, deliberately.
                CacheDirectory = "domjudge-import";
                LoadCredential = ["admin-password:${config.sops.secrets."keys/domjudge/admin-password".path}"];
                TimeoutStartSec = "3h";
                ExecStartPre = [(lib.getExe waitApi) "+${lib.getExe seed}"];
                ExecStart = lib.getExe importAll;
              };
            };
          }
        ];

        services.nginx.virtualHosts.${domain} = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.port;
            }
          ];

          extraConfig = ''
            ${config.cosmos.services.netbird.client.proxyRealIp}
            auth_request /oauth2/auth;
            error_page 401 = @redirectToAuth2ProxyLogin;
            auth_request_set $auth_user $upstream_http_x_auth_request_preferred_username;
            client_max_body_size 256m;
          '';

          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString containerPort}";
              # The recommended include sends X-Forwarded-Proto $scheme (http);
              # a second proxy_set_header would duplicate it.
              recommendedProxySettings = false;
              # X-Forwarded-Proto https makes the container's nginx set
              # HTTPS=on. Setting Remote-User replaces any client-sent value.
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header Remote-User $auth_user;
                proxy_read_timeout 600s;
              '';
            };

            "= /oauth2/auth" = {
              proxyPass = "http://127.0.0.1:${toString oauthPort}/oauth2/auth";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header Content-Length "";
                proxy_pass_request_body off;
              '';
            };

            "/oauth2/" = {
              # No trailing slash: /oauth2/start must reach oauth2-proxy whole.
              proxyPass = "http://127.0.0.1:${toString oauthPort}";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header X-Auth-Request-Redirect https://$host$request_uri;
              '';
            };

            "@redirectToAuth2ProxyLogin" = {
              return = "307 https://${domain}/oauth2/start?rd=https://$host$request_uri";
              extraConfig = "auth_request off;";
            };
          };
        };
      };
    };
  };
}
