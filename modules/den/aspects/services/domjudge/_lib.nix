# domjudge/_lib — shared by the services.domjudge aspect files.
rec {
  # The domserver, published on 127.0.0.1 only (default.nix).
  containerPort = 8093;
  api = "http://127.0.0.1:${toString containerPort}/api/v4";

  # A oneshot that drives the domserver API as admin. It waits for the API
  # (the first start installs the DB first), runs `rootSql` as root inside
  # the MariaDB container if given, then `text` with $api, a curlrc in its
  # cache dir, and `dj` (curl that fails on HTTP errors).
  # RemainAfterExit: a changed script restarts it on switch.
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
