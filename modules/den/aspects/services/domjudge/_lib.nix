# _lib — constants and the API-job helper shared by the services.domjudge files.
rec {
  containerPort = 8093;
  api = "http://127.0.0.1:${toString containerPort}/api/v4";

  # Ids must stay distinct: the id is the judgedaemon's -n, pinning its runs to CPU <id>.
  # CPU n + 36 is CPU n's hyperthread sibling (2 sockets x 18 cores x 2).
  judgehostIds = [0 1 2 3];
  judgehostContainer = id: "domjudge-judgehost-${toString id}";
  judgehostSibling = id: id + 36;
  # Every CPU but judgehostIds and their siblings; update together with judgehostIds.
  otherCpus = "4-35,40-71";
  # The base clock holds ±1.5% under any load where turbo varies ±8%;
  # languages.nix's time factors are fitted at this clock.
  judgeKHz = 2100000;

  # Oneshot driving the domserver API as admin: `rootSql` runs as MariaDB root, then `text` with
  # $api and `dj` (curl failing on HTTP errors). RemainAfterExit makes a changed script rerun on switch.
  mkApiJob = {
    config,
    lib,
    pkgs,
  }: {
    name,
    description,
    text,
    runtimeInputs ? [],
    rootSql ? null,
  }: let
    waitApi = pkgs.writeShellApplication {
      name = "domjudge-wait-api";
      runtimeInputs = with pkgs; [coreutils curl];
      text = ''
        for _ in $(seq 120); do
          [ "$(curl -s -o /dev/null -w '%{http_code}' ${api}/info || true)" = 200 ] && exit 0
          sleep 5
        done
        echo "domserver API not up after 10 minutes" >&2
        exit 1
      '';
    };
    sql = pkgs.writeShellApplication {
      name = "${name}-sql";
      runtimeInputs = [config.virtualisation.podman.package];
      text = ''
        # shellcheck disable=SC2016 # expanded inside the container
        podman exec -i domjudge-mariadb sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" domjudge' <<'SQL'
        ${rootSql}
        SQL
      '';
    };
    job = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [coreutils curl] ++ runtimeInputs;
      text = ''
        api=${api}
        umask 077
        printf 'user = "admin:%s"\n' "$(<"$CREDENTIALS_DIRECTORY/admin-password")" >"$CACHE_DIRECTORY/curlrc"
        dj() { curl -sS --fail-with-body -K "$CACHE_DIRECTORY/curlrc" "$@"; }

        ${text}
      '';
    };
  in {
    inherit description;
    wantedBy = ["multi-user.target"];
    requires = ["podman-domjudge-domserver.service"];
    after = ["podman-domjudge-domserver.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      DynamicUser = true;
      CacheDirectory = name;
      LoadCredential = ["admin-password:${config.sops.secrets."keys/domjudge/admin-password".path}"];
      ExecStartPre = [(lib.getExe waitApi)] ++ lib.optional (rootSql != null) "+${lib.getExe sql}";
      ExecStart = lib.getExe job;
    };
  };
}
