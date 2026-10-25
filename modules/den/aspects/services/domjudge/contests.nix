# services.domjudge.contests — recent CHipCie contests as open practice
# contests (started at import, ten years long, no freeze), the admin account,
# and none of DOMjudge's example data.
{den, ...}: {
  den.aspects.services.domjudge.contests = {
    includes = [den.aspects.services.domjudge];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (import ./_lib.nix) api mkApiJob;

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
    in {
      systemd.services.domjudge-import = lib.mkMerge [
        (mkApiJob {inherit config lib pkgs;} {
          name = "domjudge-import";
          description = "Import CHipCie contests into DOMjudge";
          runtimeInputs = with pkgs; [jq importContest];
          # The install loads DOMjudge's example data.
          rootSql = ''
            DELETE FROM contest WHERE externalid = 'demo';
            DELETE FROM problem WHERE externalid IN ('hello', 'fltcmp', 'boolfind');
            DELETE FROM executable WHERE execid = 'boolfind_cmp';
            DELETE FROM user WHERE username = 'demo';
            DELETE FROM team WHERE externalid = 'exteam';
            DELETE FROM team_affiliation WHERE externalid = 'utrecht';
            DELETE FROM judgehost WHERE hostname = 'example-judgehost1';
          '';
          text = ''
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
        })
        {
          wants = ["network-online.target"];
          after = ["network-online.target"];
          # Up to ~0.9 GB per contest in its cache dir, on the unpersisted root.
          serviceConfig.TimeoutStartSec = "3h";
        }
      ];
    };
  };
}
