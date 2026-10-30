# services.domjudge — the DOMjudge programming-contest judge: MariaDB, the
# domserver and one judgehost as podman containers. The files beside this one
# add what makes it judge.lvdar.nl: sso.nix (kanidm login and publishing),
# languages.nix (toolchains beyond the image's) and contests.nix (CHipCie).
#
# The domserver trusts REMOTE_USER (_files/start.ro/20-remote-user.py):
# anything that can reach 127.0.0.1:8093 or the podman network can claim any
# user. sso.nix's vhost is the only way in that sets it; its /api/ location
# clears the header and leaves the domserver's own basic auth.
#
# The image digests are the PHP2Shell fix: this domserver build carries
# php8.3-fpm 8.3.6-0ubuntu0.24.04.13; earlier builds of the 9.0.1 tag are
# vulnerable. Bump domserver and judgehost together.
{...}: let
  inherit (import ./_lib.nix) containerPort;
in {
  den.aspects.services.domjudge.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
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
  in {
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
        volumes = ["${./_files/start.ro}:/scripts/start.ro:ro"];
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
        volumes = ["/sys/fs/cgroup:/sys/fs/cgroup"];
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
      }
    ];
  };
}
